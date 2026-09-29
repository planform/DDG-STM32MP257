#!/bin/bash
# Generate FWU metadata for the current single-image, two-bank eMMC layout.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf '%s\n' 'Run this script with bash; do not source it.'
    return 1
fi

set -o pipefail

ddg_metadata_prepare() {
    local script_dir tool name
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$script_dir/env-a35.sh" || return 1
    export LC_ALL=C LANG=C

    DDG_METADATA_CONF="$DDG_PROJECT_ROOT/boards/ddg-stm32mp257/flash/fwu-metadata.conf"
    DDG_METADATA_DIR="$DDG_PROJECT_ROOT/deploy/ddg-stm32mp257/flash/emmc"
    local -a required=(FWU_VERSION FWU_IMAGE_COUNT FWU_BANK_COUNT
        FWU_ACTIVE_BANK FWU_PREVIOUS_BANK FWU_BANK_STATES
        FWU_LOCATION_GUID FWU_FIP_TYPE_GUID FWU_FIP_A_GUID FWU_FIP_B_GUID)
    # Do not silently inherit a missing setting from the caller's environment.
    unset "${required[@]}"
    if [[ ! -f "$DDG_METADATA_CONF" || ! -r "$DDG_METADATA_CONF" ]]; then
        msg "Configuration missing or unreadable: $DDG_METADATA_CONF" METADATA err
        return 1
    fi
    source "$DDG_METADATA_CONF" || return 1
    for name in "${required[@]}"; do
        if [[ -z "${!name}" ]]; then
            msg "Missing configuration value: $name" METADATA err
            return 1
        fi
    done
    if [[ "$FWU_VERSION" != 2 || "$FWU_IMAGE_COUNT" != 1 || "$FWU_BANK_COUNT" != 2 ]]; then
        msg "This layout requires version 2, one image and two banks." METADATA err
        return 1
    fi
    if [[ ! "$FWU_ACTIVE_BANK" =~ ^[01]$ || ! "$FWU_PREVIOUS_BANK" =~ ^[01]$ ||
          ! "$FWU_BANK_STATES" =~ ^[AVI],[AVI]$ ]]; then
        msg "Bank indices must be 0 or 1; bank states must be two comma-separated A/V/I values." METADATA err
        return 1
    fi
    for tool in mkfwumdata python3 mktemp mv; do
        command -v "$tool" >/dev/null || {
            msg "Required tool not found: $tool" METADATA err
            return 1
        }
    done
    mkdir -p -- "$DDG_METADATA_DIR" || return 1
}

ddg_metadata_generate() (
    local stage
    stage="$(mktemp -d "$DDG_METADATA_DIR/.metadata.XXXXXX")" || return 1
    trap 'rm -rf -- "$stage"' EXIT

    mkfwumdata -g -v "$FWU_VERSION" -i "$FWU_IMAGE_COUNT" -b "$FWU_BANK_COUNT" \
        -a "$FWU_ACTIVE_BANK" -p "$FWU_PREVIOUS_BANK" -s "$FWU_BANK_STATES" \
        "$FWU_LOCATION_GUID,$FWU_FIP_TYPE_GUID,$FWU_FIP_A_GUID,$FWU_FIP_B_GUID" \
        "$stage/metadata.bin" || {
            msg "Generation failed; previous metadata retained." METADATA err
            return 1
        }

    # Parse the exact little-endian FWU v2 structure used by this TF-A version.
    # Explicit checks (not Python assertions) also run under PYTHONOPTIMIZE.
    if ! python3 - "$stage/metadata.bin" "$FWU_ACTIVE_BANK" "$FWU_PREVIOUS_BANK" \
        "$FWU_BANK_STATES" "$FWU_LOCATION_GUID" "$FWU_FIP_TYPE_GUID" \
        "$FWU_FIP_A_GUID" "$FWU_FIP_B_GUID" <<'PY'
import struct
import sys
import uuid
import zlib
from pathlib import Path

def check(condition, message):
    if not condition:
        raise ValueError(message)

try:
    path, active, previous, states, location, image_type, bank_a, bank_b = sys.argv[1:]
    data = Path(path).read_bytes()
    check(len(data) == 120, 'Expected a 120-byte single-image, two-bank metadata file')
    crc, version, actual_active, actual_previous, size, offset, reserved = struct.unpack_from('<IIIIIHH', data)
    check(crc == zlib.crc32(data[4:]) & 0xffffffff, 'CRC32 mismatch')
    check((version, size, offset) == (2, 120, 32), 'Invalid version, size or descriptor offset')
    check((actual_active, actual_previous) == (int(active), int(previous)), 'Bank index mismatch')
    codes = {'A': 0xfc, 'V': 0xfe, 'I': 0xff}
    check(data[24:28] == bytes([codes[s] for s in states.split(',')] + [0xff, 0xff]), 'Bank state mismatch')
    check(reserved == 0 and data[28:32] == bytes(4), 'Nonzero reserved header fields')
    check(struct.unpack_from('<BBHHH', data, offset) == (2, 0, 1, 80, 24), 'Invalid image descriptor')
    for pos, expected, label in [(40, image_type, 'image type'), (56, location, 'location'),
                                 (72, bank_a, 'bank A'), (96, bank_b, 'bank B')]:
        check(uuid.UUID(bytes_le=data[pos:pos + 16]) == uuid.UUID(expected), f'{label} GUID mismatch')
    check(uuid.UUID(bank_a) != uuid.UUID(bank_b), 'Bank A and B must use distinct partition GUIDs')
    for pos in (88, 112):
        check(struct.unpack_from('<II', data, pos) == (1, 0), 'Invalid image acceptance or reserved field')
except (OSError, ValueError, KeyError, struct.error) as error:
    print(f'Metadata verification failed: {error}')
    sys.exit(1)
print(f'Verified FWU v{version}: {size} bytes, CRC32=0x{crc:08x}, active={active}, previous={previous}, states={states}')
PY
    then
        msg "Validation failed; previous metadata retained." METADATA err
        return 1
    fi
    # Same-filesystem rename publishes only a fully validated binary.
    mv -f -- "$stage/metadata.bin" "$DDG_METADATA_DIR/metadata.bin" || {
        msg "Failed to publish metadata: $DDG_METADATA_DIR" METADATA err
        return 1
    }
)

main() {
    ddg_metadata_prepare || return 1
    ddg_metadata_generate || return 1
    msg "FWU metadata generated and verified" METADATA ext
    msg "Output: $DDG_METADATA_DIR/metadata.bin" METADATA info
}

main "$@"
