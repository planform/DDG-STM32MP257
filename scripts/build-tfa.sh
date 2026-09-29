#!/bin/bash
# Run with: make tfa (or bash /path/to/scripts/build-tfa.sh).
# Execute in a separate process so SDK setup does not change the caller's shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf '%s\n' 'Run this script with bash; do not source it.'
    return 1
fi

set -o pipefail

ddg_tfa_prepare() {
    local script_dir tool file
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source "$script_dir/env-a35.sh" || return 1
    source "$script_dir/prepare-source.sh" || return 1

    # Keep the validated board and source versions together.
    local tfa_version="tf-a-stm32mp-v2.10.24-stm32mp-r3.1"
    local ddr_version="stm32mp-ddr-phy-A2022.11"
    DDG_TFA_BOARD="stm32mp257d-ddg"
    DDG_TFA_SRC="$DDG_LINUX_SOURCE_ROOT/$tfa_version-r0/$tfa_version"
    DDG_TFA_BOARD_DIR="$DDG_PROJECT_ROOT/boards/ddg-stm32mp257/tf-a"
    DDG_TFA_BUILD_DIR="$DDG_PROJECT_ROOT/build/ddg-stm32mp257/tf-a/emmc"
    DDG_TFA_DEPLOY_DIR="$DDG_PROJECT_ROOT/deploy/ddg-stm32mp257/tf-a/emmc"
    DDG_TFA_LOG="$DDG_TFA_BUILD_DIR/build.log"
    DDG_TFA_DDR_DIR="$DDG_LINUX_SOURCE_ROOT/$ddr_version-r0/$ddr_version/stm32mp2"
    DDG_TFA_CROSS_COMPILE="$OECORE_NATIVE_SYSROOT/usr/share/gcc-aarch64-none-elf/bin/aarch64-none-elf-"

    for tool in make dtc tee nproc; do
        command -v "$tool" >/dev/null || {
            msg "Required tool not found: $tool" TFA err
            return 1
        }
    done
    if [[ ! -x "${DDG_TFA_CROSS_COMPILE}gcc" ]]; then
        msg "TF-A compiler not found: ${DDG_TFA_CROSS_COMPILE}gcc" TFA err
        return 1
    fi
    mkdir -p -- "$DDG_TFA_BUILD_DIR" || return 1
    if ! (
        ddg_prepare_source "$DDG_LINUX_SOURCE_ROOT/$tfa_version-r0" \
            "$tfa_version" "$DDG_PROJECT_ROOT/patches/tf-a" TFA || exit 1
        ddg_prepare_source "$DDG_LINUX_SOURCE_ROOT/$ddr_version-r0" \
            "$ddr_version" "$DDG_PROJECT_ROOT/patches/ddr-phy" DDR_PHY || exit 1
    ) 2>&1 | tee "$DDG_TFA_BUILD_DIR/prepare.log"; then
        msg "Source preparation failed. See $DDG_TFA_BUILD_DIR/prepare.log" TFA err
        return 1
    fi
    for file in \
        "$DDG_TFA_SRC/Makefile" \
        "$DDG_TFA_BOARD_DIR/$DDG_TFA_BOARD.dts" \
        "$DDG_TFA_BOARD_DIR/$DDG_TFA_BOARD-fw-config.dts" \
        "$DDG_TFA_DDR_DIR/ddr4_pmu_train.bin"; do
        if [[ ! -r "$file" || ! -s "$file" ]]; then
            msg "Required file missing, empty or unreadable: $file" TFA err
            return 1
        fi
    done

    DDG_TFA_JOBS="$(nproc)" || return 1
    mkdir -p -- "$DDG_TFA_BUILD_DIR" "$DDG_TFA_DEPLOY_DIR" || return 1
}

ddg_tfa_build() {
    # TF-A supplies its own flags; Linux SDK flags are inappropriate here.
    unset CC CXX CPP AS AR LD NM OBJCOPY OBJDUMP RANLIB STRIP
    unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

    msg "Building $DDG_TFA_BOARD (eMMC, DDR4, debug)" TFA info
    msg "Log: $DDG_TFA_LOG" TFA info
    # pipefail catches both make failures and failures to write the log.
    if ! make -C "$DDG_TFA_SRC" -j"$DDG_TFA_JOBS" \
        PLAT=stm32mp2 \
        ARCH=aarch64 \
        ARM_ARCH_MAJOR=8 \
        CROSS_COMPILE="$DDG_TFA_CROSS_COMPILE" \
        BUILD_PLAT="$DDG_TFA_BUILD_DIR" \
        TFA_EXTERNAL_DT="$DDG_TFA_BOARD_DIR" \
        DTB_FILE_NAME="$DDG_TFA_BOARD.dtb" \
        STM32MP25=1 \
        STM32MP_DDR4_TYPE=1 \
        STM32MP_DDR_FW_PATH="$DDG_TFA_DDR_DIR" \
        STM32MP_EMMC=1 \
        SPD=opteed \
        PSA_FWU_SUPPORT=1 \
        DEBUG=1 \
        LOG_LEVEL=40 \
        all dtbs 2>&1 | tee "$DDG_TFA_LOG"; then
        msg "Build or log write failed; deployment skipped. Log: $DDG_TFA_LOG" TFA err
        return 1
    fi
}

ddg_tfa_deploy() {
    local file
    local -a artifacts=(
        "$DDG_TFA_BUILD_DIR/tf-a-$DDG_TFA_BOARD.stm32"
        "$DDG_TFA_BUILD_DIR/bl31.bin"
        "$DDG_TFA_BUILD_DIR/fdts/$DDG_TFA_BOARD-bl31.dtb"
        "$DDG_TFA_BUILD_DIR/fdts/$DDG_TFA_BOARD-fw-config.dtb"
        "$DDG_TFA_DDR_DIR/ddr4_pmu_train.bin"
    )

    # Check the entire set before replacing any previously deployed files.
    for file in "${artifacts[@]}"; do
        if [[ ! -r "$file" || ! -s "$file" ]]; then
            msg "Required artifact missing, empty or unreadable: $file" TFA err
            return 1
        fi
    done
    cp -- "${artifacts[@]}" "$DDG_TFA_DEPLOY_DIR/" || {
        msg "Failed to copy artifacts to: $DDG_TFA_DEPLOY_DIR" TFA err
        return 1
    }
}

main() {
    ddg_tfa_prepare || return 1
    ddg_tfa_build || return 1
    ddg_tfa_deploy || return 1

    msg "TF-A build and artifact collection complete" TFA ext
    msg "Artifacts: $DDG_TFA_DEPLOY_DIR" TFA info
    msg "Log      : $DDG_TFA_LOG" TFA info
}

main "$@"
