#!/bin/bash
# Pack existing deployed artifacts: make fip. This does not rebuild components.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf '%s\n' 'Run this script with bash; do not source it.'
    return 1
fi

set -o pipefail

ddg_fip_prepare() {
    local script_dir tool index file
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$script_dir/env-a35.sh" || return 1
    export LC_ALL=C LANG=C

    local deploy_root="$DDG_PROJECT_ROOT/deploy/ddg-stm32mp257"
    local tfa_dir="$deploy_root/tf-a/emmc"
    local optee_dir="$deploy_root/optee/runtime"
    local uboot_dir="$deploy_root/u-boot/runtime"
    DDG_FIP_DIR="$deploy_root/fip/emmc"
    # Parallel arrays keep every input paired with its fiptool option.
    DDG_FIP_OPTIONS=(ddr-fw soc-fw soc-fw-config fw-config
        tos-fw tos-fw-extra1 tos-fw-extra2 nt-fw hw-config)
    DDG_FIP_INPUTS=(
        "$tfa_dir/ddr4_pmu_train.bin"
        "$tfa_dir/bl31.bin"
        "$tfa_dir/stm32mp257d-ddg-bl31.dtb"
        "$tfa_dir/stm32mp257d-ddg-fw-config.dtb"
        "$optee_dir/tee-header_v2.bin"
        "$optee_dir/tee-pager_v2.bin"
        "$optee_dir/tee-pageable_v2.bin"
        "$uboot_dir/u-boot-nodtb.bin"
        "$uboot_dir/u-boot.dtb"
    )
    for tool in fiptool cmp mktemp cp mv; do
        command -v "$tool" >/dev/null || {
            msg "Required tool not found: $tool" FIP err
            return 1
        }
    done
    for index in "${!DDG_FIP_INPUTS[@]}"; do
        file="${DDG_FIP_INPUTS[$index]}"
        if [[ ! -f "$file" || ! -r "$file" ]]; then
            msg "Required input missing or unreadable: $file" FIP err
            return 1
        fi
        # CFG_WITH_PAGER=n legitimately produces an empty extra2 image.
        if [[ "${DDG_FIP_OPTIONS[$index]}" != tos-fw-extra2 && ! -s "$file" ]]; then
            msg "Required input is empty: $file" FIP err
            return 1
        fi
    done
    mkdir -p -- "$DDG_FIP_DIR" || return 1
}

ddg_fip_pack() (
    # Subshell scopes the cleanup trap. Use the output filesystem so the final
    # rename replaces fip.bin atomically, after successful verification.
    local stage index option file
    local -a create_args=() unpack_args=()
    stage="$(mktemp -d "$DDG_FIP_DIR/.pack.XXXXXX")" || return 1
    trap 'rm -rf -- "$stage"' EXIT
    mkdir -- "$stage/inputs" "$stage/unpacked" || return 1

    for index in "${!DDG_FIP_INPUTS[@]}"; do
        option="${DDG_FIP_OPTIONS[$index]}"
        file="$stage/inputs/$option.bin"
        cp -- "${DDG_FIP_INPUTS[$index]}" "$file" || return 1
        create_args+=("--$option" "$file")
        # fiptool omits empty images from unpack/info output.
        [[ ! -s "$file" ]] || unpack_args+=("--$option" "$option.bin")
    done

    msg "Packing deployed TF-A, OP-TEE, U-Boot and DDR firmware" FIP info
    fiptool create "${create_args[@]}" "$stage/fip.bin" || {
        msg "Packing failed; previous FIP retained." FIP err
        return 1
    }
    fiptool info "$stage/fip.bin" > "$stage/fip-info.txt" || {
        msg "FIP inspection failed; previous FIP retained." FIP err
        return 1
    }
    fiptool unpack --out "$stage/unpacked" "${unpack_args[@]}" "$stage/fip.bin" || {
        msg "FIP unpack failed; previous FIP retained." FIP err
        return 1
    }
    for option in "${DDG_FIP_OPTIONS[@]}"; do
        file="$stage/inputs/$option.bin"
        [[ -s "$file" ]] || continue
        cmp -s -- "$file" "$stage/unpacked/$option.bin" || {
            msg "FIP content mismatch: $option. Previous FIP retained." FIP err
            return 1
        }
    done

    # All packaging and content checks have passed before publishing outputs.
    mv -f -- "$stage/fip-info.txt" "$DDG_FIP_DIR/fip-info.txt" &&
        mv -f -- "$stage/fip.bin" "$DDG_FIP_DIR/fip.bin" || {
            msg "Failed to publish FIP outputs: $DDG_FIP_DIR" FIP err
            return 1
        }
)

main() {
    ddg_fip_prepare || return 1
    ddg_fip_pack || return 1
    msg "FIP packed and contents verified" FIP ext
    msg "Image: $DDG_FIP_DIR/fip.bin" FIP info
    msg "Index: $DDG_FIP_DIR/fip-info.txt" FIP info
}

main "$@"
