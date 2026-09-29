#!/bin/bash
# Shared by the component build scripts; requires common.sh (msg).
# Arguments: package directory, extracted directory name, project patch directory,
#            log context, optional extra archive (extracted inside the source tree).
ddg_prepare_source() (
    local package="$1" name="$2" project_patches="$3" context="$4" extra="${5:-}"
    local src="$package/$name" archive="$package/$name-r0.tar.xz"
    local marker="$src/.ddg-source-state" stage="" digest old_digest
    local series line patch_name option rest patch_file tool
    local -a inputs=("$archive") patches=()
    export LC_ALL=C

    for tool in tar patch sha256sum mktemp flock python3; do
        command -v "$tool" >/dev/null || {
            msg "Required source preparation tool not found: $tool" "$context" err
            return 1
        }
    done
    [[ -z "$extra" ]] || inputs+=("$extra")
    # Both ST and project series accept 'file.patch' or 'file.patch -p1'.
    for series in "$package/series" "$project_patches/series"; do
        [[ -f "$series" ]] || continue
        inputs+=("$series")
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            read -r patch_name option rest <<< "$line"
            [[ -n "$patch_name" ]] || continue
            if [[ "$patch_name" == /* || "$patch_name" == *..* ||
                  -n "$rest" || ( -n "$option" && "$option" != -p1 ) ]]; then
                msg "Unsupported series entry in $series: $line" "$context" err
                return 1
            fi
            patch_file="${series%/*}/$patch_name"
            patches+=("$patch_file")
            inputs+=("$patch_file")
        done < "$series"
    done
    # Never silently ignore patches that have no ordering file.
    for series in "$package" "$project_patches"; do
        if [[ ! -f "$series/series" ]] && compgen -G "$series/*.patch" >/dev/null; then
            msg "Patch files found without a series file: $series" "$context" err
            return 1
        fi
    done
    for patch_file in "${inputs[@]}"; do
        if [[ ! -f "$patch_file" || ! -r "$patch_file" ]]; then
            msg "Required source input missing or unreadable: $patch_file" "$context" err
            return 1
        fi
    done
    # Serialize preparation of this package, including first-time extraction.
    exec 9> "$package/.ddg-source.lock" || return 1
    flock -x 9 || return 1
    digest="$(sha256sum "${inputs[@]}" | sha256sum)" || return 1
    digest="v1 ${digest%% *}"
    if [[ -f "$marker" ]]; then
        old_digest="$(cat "$marker")" || return 1
        if [[ "$old_digest" != "$digest" ]]; then
            msg "Source inputs changed. Preserve/rename the source and component build directories before preparing again: $src" "$context" err
            return 1
        fi
        msg "Source already prepared: $src" "$context" info
        return 0
    fi

    # Prepare in a private directory; failed extraction/patching never leaves a
    # half-patched source tree at the final path.
    stage="$(mktemp -d "$package/.ddg-prepare.XXXXXX")" || return 1
    trap 'rm -rf -- "$stage"' EXIT
    msg "Extracting: $archive" "$context" info
    tar -xf "$archive" -C "$stage" || return 1
    [[ -d "$stage/$name" ]] || {
        msg "Archive does not contain the expected directory: $name" "$context" err
        return 1
    }
    if [[ -n "$extra" ]]; then
        tar -xf "$extra" -C "$stage/$name" || return 1
    fi
    for patch_file in "${patches[@]}"; do
        msg "Applying: $patch_file" "$context" info
        patch --batch --forward --fuzz=0 -d "$stage/$name" -p1 -i "$patch_file" || {
            msg "Patch failed; existing source retained: $patch_file" "$context" err
            return 1
        }
    done
    if [[ -n "$extra" ]]; then
        # Required by the OP-TEE Developer Package instructions.
        chmod 755 "$stage/$name/scripts/bin_to_c.py" || return 1
    fi

    if [[ -e "$src" ]]; then
        # Adopt an existing manually prepared tree only if every baseline file
        # matches. Extra build/debug files are allowed; local edits are retained.
        python3 - "$stage/$name" "$src" <<'PY' || return 1
import os
import sys
from pathlib import Path
baseline, existing = map(Path, sys.argv[1:])
for source in baseline.rglob('*'):
    target = existing / source.relative_to(baseline)
    if source.is_symlink():
        match = target.is_symlink() and os.readlink(source) == os.readlink(target)
    elif source.is_dir():
        match = target.is_dir() and not target.is_symlink()
    else:
        match = (target.is_file() and not target.is_symlink()
                 and source.read_bytes() == target.read_bytes())
    if not match:
        print(f'Existing source differs from prepared baseline: {target}')
        print('Source was NOT changed. Preserve/rename the source and component build directories before preparing again.')
        sys.exit(1)
PY
        if [[ -n "$extra" && ! -x "$src/scripts/bin_to_c.py" ]]; then
            msg "Run chmod 755 on $src/scripts/bin_to_c.py, then retry." "$context" err
            return 1
        fi
        printf '%s\n' "$digest" > "$marker" || return 1
        msg "Existing source verified and adopted: $src" "$context" ext
    else
        printf '%s\n' "$digest" > "$stage/$name/.ddg-source-state" || return 1
        mv -- "$stage/$name" "$src" || return 1
        msg "Source prepared: $src" "$context" ext
    fi
)
