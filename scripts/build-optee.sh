#!/bin/bash
# Run with make optee, or bash /path/to/scripts/build-optee.sh.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf '%s\n' 'Run this script with bash; do not source it.'
    return 1
fi

set -o pipefail

ddg_optee_prepare() {
    local script_dir tool file
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$script_dir/env-a35.sh" || return 1
    source "$script_dir/prepare-source.sh" || return 1

    local optee_version="optee-os-stm32mp-4.0.0-stm32mp-r3.1"
    DDG_OPTEE_BOARD="stm32mp257d-ddg"
    DDG_OPTEE_SRC="$DDG_LINUX_SOURCE_ROOT/$optee_version-r0/$optee_version"
    DDG_OPTEE_BOARD_DIR="$DDG_PROJECT_ROOT/boards/ddg-stm32mp257/optee"
    DDG_OPTEE_BUILD_DIR="$DDG_PROJECT_ROOT/build/ddg-stm32mp257/optee/runtime"
    DDG_OPTEE_DEPLOY_DIR="$DDG_PROJECT_ROOT/deploy/ddg-stm32mp257/optee/runtime"
    DDG_OPTEE_LOG="$DDG_OPTEE_BUILD_DIR/build.log"
    DDG_OPTEE_CROSS_COMPILE="$CROSS_COMPILE"

    # The SDK needs these flags to locate libgcc.a; do not discard them.
    DDG_OPTEE_CFLAGS="${LIBGCC_LOCATE_CFLAGS:-}"
    if [[ -z "$DDG_OPTEE_CFLAGS" ]]; then
        msg "SDK did not provide LIBGCC_LOCATE_CFLAGS." OPTEE err
        return 1
    fi
    for tool in make dtc tee nproc python3 cmake "${DDG_OPTEE_CROSS_COMPILE}gcc"; do
        command -v "$tool" >/dev/null || {
            msg "Required tool not found: $tool" OPTEE err
            return 1
        }
    done
    mkdir -p -- "$DDG_OPTEE_BUILD_DIR" || return 1
    if ! ddg_prepare_source "$DDG_LINUX_SOURCE_ROOT/$optee_version-r0" \
        "$optee_version" "$DDG_PROJECT_ROOT/patches/optee" OPTEE \
        "$DDG_LINUX_SOURCE_ROOT/$optee_version-r0/fonts.tar.gz" \
        2>&1 | tee "$DDG_OPTEE_BUILD_DIR/prepare.log"; then
        msg "Source preparation failed. See $DDG_OPTEE_BUILD_DIR/prepare.log" OPTEE err
        return 1
    fi
    for file in \
        "$DDG_OPTEE_SRC/Makefile" \
        "$DDG_OPTEE_BOARD_DIR/$DDG_OPTEE_BOARD.dts" \
        "$DDG_OPTEE_BOARD_DIR/$DDG_OPTEE_BOARD-rcc.dtsi" \
        "$DDG_OPTEE_BOARD_DIR/$DDG_OPTEE_BOARD-resmem.dtsi" \
        "$DDG_OPTEE_BOARD_DIR/$DDG_OPTEE_BOARD-rif.dtsi"; do
        if [[ ! -r "$file" || ! -s "$file" ]]; then
            msg "Required file missing, empty or unreadable: $file" OPTEE err
            return 1
        fi
    done
    DDG_OPTEE_JOBS="$(nproc)" || return 1
    mkdir -p -- "$DDG_OPTEE_BUILD_DIR" "$DDG_OPTEE_DEPLOY_DIR/debug" || return 1
}

ddg_optee_build() {
    # Use a locale available to both host and SDK tools, only in this process.
    export LC_ALL=C
    # OP-TEE supplies its own compiler flags. Restore only libgcc lookup flags.
    unset CC CXX CPP AS AR LD NM OBJCOPY OBJDUMP RANLIB STRIP
    unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

    msg "Building $DDG_OPTEE_BOARD (runtime, AArch64, debug)" OPTEE info
    msg "Log: $DDG_OPTEE_LOG" OPTEE info
    # pipefail also detects tee failing to write the log.
    if ! make -C "$DDG_OPTEE_SRC" -j"$DDG_OPTEE_JOBS" \
        PLATFORM=stm32mp2 \
        ARCH=arm \
        CFG_ARM64_core=y \
        CFG_STM32MP25=y \
        CROSS_COMPILE_core="$DDG_OPTEE_CROSS_COMPILE" \
        CROSS_COMPILE_ta_arm64="$DDG_OPTEE_CROSS_COMPILE" \
        supported-ta-targets=ta_arm64 \
        CFG_EXT_DTS="$DDG_OPTEE_BOARD_DIR" \
        CFG_EMBED_DTB_SOURCE_FILE="$DDG_OPTEE_BOARD.dts" \
        CFG_STM32MP_PROFILE=secure_and_system_services \
        CFG_TEE_CORE_DEBUG=y \
        CFG_TEE_CORE_LOG_LEVEL=2 \
        NOWERROR=1 \
        CFLAGS="$DDG_OPTEE_CFLAGS" \
        O="$DDG_OPTEE_BUILD_DIR" \
        all 2>&1 | tee "$DDG_OPTEE_LOG"; then
        msg "Build or log write failed; deployment skipped. Log: $DDG_OPTEE_LOG" OPTEE err
        return 1
    fi
}

ddg_optee_deploy() {
    local core_dir="$DDG_OPTEE_BUILD_DIR/core" file
    # Validate all four files before replacing any previous deployment.
    for file in tee-header_v2.bin tee-pager_v2.bin tee-pageable_v2.bin tee.elf; do
        if [[ ! -f "$core_dir/$file" || ! -r "$core_dir/$file" ]]; then
            msg "Required artifact missing or unreadable: $core_dir/$file" OPTEE err
            return 1
        fi
        # A build without paging legitimately produces an empty pageable image.
        if [[ "$file" != tee-pageable_v2.bin && ! -s "$core_dir/$file" ]]; then
            msg "Required artifact is empty: $core_dir/$file" OPTEE err
            return 1
        fi
    done
    cp -- "$core_dir/tee-header_v2.bin" "$core_dir/tee-pager_v2.bin" \
        "$core_dir/tee-pageable_v2.bin" "$DDG_OPTEE_DEPLOY_DIR/" &&
        cp -- "$core_dir/tee.elf" "$DDG_OPTEE_DEPLOY_DIR/debug/" || {
            msg "Failed to copy artifacts to: $DDG_OPTEE_DEPLOY_DIR" OPTEE err
            return 1
        }
}

main() {
    ddg_optee_prepare || return 1
    ddg_optee_build || return 1
    ddg_optee_deploy || return 1

    msg "OP-TEE build and artifact collection complete" OPTEE ext
    msg "Artifacts: $DDG_OPTEE_DEPLOY_DIR" OPTEE info
    msg "Log      : $DDG_OPTEE_LOG" OPTEE info
}

main "$@"
