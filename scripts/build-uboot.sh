#!/bin/bash
# Run with make uboot, or bash /path/to/scripts/build-uboot.sh.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf '%s\n' 'Run this script with bash; do not source it.'
    return 1
fi

set -o pipefail

ddg_uboot_prepare() {
    local script_dir tool file
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$script_dir/env-a35.sh" || return 1
    source "$script_dir/prepare-source.sh" || return 1

    local uboot_version="u-boot-stm32mp-v2023.10-stm32mp-r3.1"
    DDG_UBOOT_BOARD="stm32mp257d-ddg"
    DDG_UBOOT_SRC="$DDG_LINUX_SOURCE_ROOT/$uboot_version-r0/$uboot_version"
    DDG_UBOOT_BOARD_DIR="$DDG_PROJECT_ROOT/boards/ddg-stm32mp257/u-boot"
    DDG_UBOOT_BUILD_DIR="$DDG_PROJECT_ROOT/build/ddg-stm32mp257/u-boot/runtime"
    DDG_UBOOT_EXT_DTS="$DDG_PROJECT_ROOT/build/ddg-stm32mp257/u-boot/external-dt"
    DDG_UBOOT_DEPLOY_DIR="$DDG_PROJECT_ROOT/deploy/ddg-stm32mp257/u-boot/runtime"
    DDG_UBOOT_LOG="$DDG_UBOOT_BUILD_DIR/build.log"
    DDG_UBOOT_CROSS_COMPILE="$CROSS_COMPILE"
    DDG_UBOOT_KCFLAGS="${LIBGCC_LOCATE_CFLAGS:-}"
    if [[ -z "$DDG_UBOOT_KCFLAGS" ]]; then
        msg "SDK did not provide LIBGCC_LOCATE_CFLAGS." UBOOT err
        return 1
    fi
    for tool in make dtc fdtget tee nproc cmp python3 "${DDG_UBOOT_CROSS_COMPILE}gcc"; do
        command -v "$tool" >/dev/null || {
            msg "Required tool not found: $tool" UBOOT err
            return 1
        }
    done
    mkdir -p -- "$DDG_UBOOT_BUILD_DIR" || return 1
    if ! ddg_prepare_source "$DDG_LINUX_SOURCE_ROOT/$uboot_version-r0" \
        "$uboot_version" "$DDG_PROJECT_ROOT/patches/u-boot" UBOOT \
        2>&1 | tee "$DDG_UBOOT_BUILD_DIR/prepare.log"; then
        msg "Source preparation failed. See $DDG_UBOOT_BUILD_DIR/prepare.log" UBOOT err
        return 1
    fi
    for file in "$DDG_UBOOT_SRC/Makefile" \
        "$DDG_UBOOT_SRC/configs/stm32mp25_defconfig" \
        "$DDG_UBOOT_SRC/scripts/config" \
        "$DDG_UBOOT_BOARD_DIR/Makefile" \
        "$DDG_UBOOT_BOARD_DIR/$DDG_UBOOT_BOARD.dts" \
        "$DDG_UBOOT_BOARD_DIR/$DDG_UBOOT_BOARD-resmem.dtsi" \
        "$DDG_UBOOT_BOARD_DIR/$DDG_UBOOT_BOARD-u-boot.dtsi"; do
        if [[ ! -f "$file" || ! -r "$file" || ! -s "$file" ]]; then
            msg "Required file missing, empty or unreadable: $file" UBOOT err
            return 1
        fi
    done
    DDG_UBOOT_JOBS="$(nproc)" || return 1
    mkdir -p -- "$DDG_UBOOT_EXT_DTS" "$DDG_UBOOT_DEPLOY_DIR/debug" || return 1
    # U-Boot writes DTB intermediates in EXT_DTS. Keep those out of boards/.
    # Do not touch unchanged copies, so incremental DTB builds remain possible.
    for file in Makefile "$DDG_UBOOT_BOARD.dts" \
        "$DDG_UBOOT_BOARD-resmem.dtsi" "$DDG_UBOOT_BOARD-u-boot.dtsi"; do
        if ! cmp -s -- "$DDG_UBOOT_BOARD_DIR/$file" "$DDG_UBOOT_EXT_DTS/$file"; then
            cp -- "$DDG_UBOOT_BOARD_DIR/$file" "$DDG_UBOOT_EXT_DTS/" || return 1
        fi
    done
}

ddg_uboot_build() {
    # U-Boot unexports LC_ALL internally; LANG=C also covers its host tools.
    export LC_ALL=C LANG=C LANGUAGE=C
    unset CC CXX CPP AS AR LD NM OBJCOPY OBJDUMP RANLIB STRIP
    unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    local -a options=(
        -C "$DDG_UBOOT_SRC" O="$DDG_UBOOT_BUILD_DIR" ARCH=arm
        CROSS_COMPILE="$DDG_UBOOT_CROSS_COMPILE"
        KCFLAGS="$DDG_UBOOT_KCFLAGS"
        EXT_DTS="$DDG_UBOOT_EXT_DTS" DEVICE_TREE="$DDG_UBOOT_BOARD"
    )
    msg "Building $DDG_UBOOT_BOARD (stm32mp25_defconfig, eMMC)" UBOOT info
    msg "Log: $DDG_UBOOT_LOG" UBOOT info
    # Recreate the known configuration; object files remain available for reuse.
    # The && chain prevents a failed configuration from reaching compilation.
    if ! {
        make "${options[@]}" stm32mp25_defconfig &&
        bash "$DDG_UBOOT_SRC/scripts/config" --file "$DDG_UBOOT_BUILD_DIR/.config" \
            --set-str DEFAULT_DEVICE_TREE "$DDG_UBOOT_BOARD" &&
        make "${options[@]}" olddefconfig &&
        make "${options[@]}" -j"$DDG_UBOOT_JOBS" all
    } 2>&1 | tee "$DDG_UBOOT_LOG"; then
        msg "Configuration, build or log write failed; deployment skipped. Log: $DDG_UBOOT_LOG" UBOOT err
        return 1
    fi
}

ddg_uboot_deploy() {
    local file compatible
    for file in u-boot.bin u-boot-nodtb.bin u-boot.dtb u-boot; do
        if [[ ! -f "$DDG_UBOOT_BUILD_DIR/$file" ||
              ! -r "$DDG_UBOOT_BUILD_DIR/$file" || ! -s "$DDG_UBOOT_BUILD_DIR/$file" ]]; then
            msg "Required artifact missing, empty or unreadable: $DDG_UBOOT_BUILD_DIR/$file" UBOOT err
            return 1
        fi
    done
    compatible="$(fdtget "$DDG_UBOOT_BUILD_DIR/u-boot.dtb" / compatible)" || return 1
    if [[ " $compatible " != *" ddg,$DDG_UBOOT_BOARD "* ]]; then
        msg "Unexpected board in built DTB: $compatible" UBOOT err
        return 1
    fi
    cp -- "$DDG_UBOOT_BUILD_DIR/u-boot.bin" "$DDG_UBOOT_BUILD_DIR/u-boot-nodtb.bin" \
        "$DDG_UBOOT_BUILD_DIR/u-boot.dtb" "$DDG_UBOOT_DEPLOY_DIR/" &&
        cp -- "$DDG_UBOOT_BUILD_DIR/u-boot" "$DDG_UBOOT_DEPLOY_DIR/debug/" || {
            msg "Failed to copy artifacts to: $DDG_UBOOT_DEPLOY_DIR" UBOOT err
            return 1
        }
}

main() {
    ddg_uboot_prepare || return 1
    ddg_uboot_build || return 1
    ddg_uboot_deploy || return 1

    msg "U-Boot build and artifact collection complete" UBOOT ext
    msg "Artifacts: $DDG_UBOOT_DEPLOY_DIR" UBOOT info
    msg "Log      : $DDG_UBOOT_LOG" UBOOT info
}

main "$@"
