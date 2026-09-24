#!/bin/bash

# Source this file from Bash or Zsh. Capture its path before entering functions.
if [ -n "${ZSH_VERSION:-}" ]; then
    DDG_M33_SCRIPT_FILE="${(%):-%x}"
elif [ -n "${BASH_VERSION:-}" ]; then
    DDG_M33_SCRIPT_FILE="${BASH_SOURCE[0]}"
else
    printf '%s\n' "Please source this script from Bash or Zsh."
    return 1
fi

DDG_M33_SCRIPT_DIR="$(
    cd -- "$(dirname -- "$DDG_M33_SCRIPT_FILE")" && pwd -P
)" || return 1
unset DDG_M33_SCRIPT_FILE

source "$DDG_M33_SCRIPT_DIR/common.sh" || return 1

ddg_m33_project_root() {
    local proj_root

    proj_root="$(
        cd -- "$DDG_M33_SCRIPT_DIR/.." &&
        pwd -P
    )" || {
        msg "Cannot locate project root from: $DDG_M33_SCRIPT_DIR" M33_ENV err
        return 1
    }

    export DDG_PROJECT_ROOT="$proj_root"
}

# Keep the original function name; conflicts now trigger cleanup, not rejection.
# This list matches the installed OpenSTLinux v26.06.10 SDK and its setup.d files.
ddg_m33_check_conflict() {
    if [[ "${DDG_ACTIVE_ENV:-}" != "a35" &&
          "${DDG_ACTIVE_ENV:-}" != "linux" &&
          -z "${SDKTARGETSYSROOT:-}" &&
          -z "${OECORE_NATIVE_SYSROOT:-}" ]]; then
        return 0
    fi

    local native_root="${OECORE_NATIVE_SYSROOT:-}"
    # Fallback for a partially loaded SDK whose target sysroot is still known.
    if [[ -z "$native_root" && -n "${SDKTARGETSYSROOT:-}" ]]; then
        native_root="${SDKTARGETSYSROOT%/*}/x86_64-ostl_sdk-linux"
    fi
    if [[ -z "$native_root" ]]; then
        native_root="$DDG_PROJECT_ROOT/openstlinux/sdk-installed/sysroots/x86_64-ostl_sdk-linux"
    fi
    native_root="${native_root%/}"

    # Remove SDK entries only. Preserve user entries, ordering and empty entries.
    local remaining="${PATH:-}" entry cleaned_path="" kept=0 more=0
    while :; do
        more=0
        case "$remaining" in
            *:*) entry="${remaining%%:*}"; remaining="${remaining#*:}"; more=1 ;;
            *)   entry="$remaining" ;;
        esac
        case "$entry" in
            "$native_root"|"$native_root"/*) ;;
            *)
                if [[ "$kept" == 1 ]]; then
                    cleaned_path="$cleaned_path:$entry"
                else
                    cleaned_path="$entry"
                    kept=1
                fi
                ;;
        esac
        [[ "$more" == 1 ]] || break
    done

    # The SDK respects user certificate settings; keep those outside the SDK.
    case "${SSL_CERT_FILE:-}" in
        "$native_root"/*) unset SSL_CERT_FILE || return 1 ;;
    esac
    case "${SSL_CERT_DIR:-}" in
        "$native_root"/*) unset SSL_CERT_DIR || return 1 ;;
    esac

    # Remove only the passthrough names added by the SDK's openssl.sh.
    if [[ -n "${BB_ENV_PASSTHROUGH_ADDITIONS:-}" ]]; then
        local name passthrough=""
        while IFS= read -r name; do
            case "$name" in
                ''|OPENSSL_CONF|OPENSSL_MODULES|OPENSSL_ENGINES|SSL_CERT_DIR|SSL_CERT_FILE) ;;
                *) passthrough="${passthrough:+$passthrough }$name" ;;
            esac
        done < <(printf '%s\n' "$BB_ENV_PASSTHROUGH_ADDITIONS" | tr '[:space:]' '\n')
        if [[ -n "$passthrough" ]]; then
            export BB_ENV_PASSTHROUGH_ADDITIONS="$passthrough"
        else
            unset BB_ENV_PASSTHROUGH_ADDITIONS || return 1
        fi
    fi

    unset SDKTARGETSYSROOT PKG_CONFIG_SYSROOT_DIR PKG_CONFIG_PATH CONFIG_SITE \
        OECORE_NATIVE_SYSROOT OECORE_TARGET_SYSROOT OECORE_ACLOCAL_OPTS \
        OECORE_BASELIB OECORE_TARGET_ARCH OECORE_TARGET_OS \
        OECORE_DISTRO_VERSION OECORE_SDK_VERSION OECORE_TUNE_CCARGS \
        CC CXX CPP AS LD GDB STRIP RANLIB OBJCOPY OBJDUMP READELF AR NM M4 \
        TARGET_PREFIX CONFIGURE_FLAGS CFLAGS CXXFLAGS LDFLAGS CPPFLAGS KCFLAGS \
        ARCH CROSS_COMPILE CMAKE_TOOLCHAIN_FILE OE_CMAKE_FIND_LIBRARY_CUSTOM_LIB_SUFFIX \
        OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES TEEC_EXPORT TA_DEV_KIT_DIR \
        LIBGCC_LOCATE_CFLAGS TFM_DEV_KIT_DIR DDG_ACTIVE_ENV \
        DDG_A35_LOADED_SDK_ROOT DDG_A35_COMPILER_VERSION || return 1

    export PATH="$cleaned_path"
    msg "Previous Linux SDK environment cleared; switching to M33." M33_ENV info
    return 0
}

ddg_m33_prepare_toolchain() {
    # find toolchain
    if [[ -z "${M33_TOOLCHAIN:-}" ]]; then
        M33_TOOLCHAIN="$DDG_PROJECT_ROOT/openstlinux/sdk-installed/sysroots/x86_64-ostl_sdk-linux/usr/share/gcc-arm-none-eabi"
    fi

    if [[ ! -x "$M33_TOOLCHAIN/bin/arm-none-eabi-gcc" ]]; then
        msg "Compiler missing or not executable: $M33_TOOLCHAIN/bin/arm-none-eabi-gcc" M33_ENV err
        return 1
    fi

    local result=""
    result=$("$M33_TOOLCHAIN/bin/arm-none-eabi-gcc" -dumpmachine) || {
        msg "Cannot query compiler target: $M33_TOOLCHAIN/bin/arm-none-eabi-gcc" M33_ENV err
        return 1
    }

    if [[ "$result" != "arm-none-eabi" ]]; then
        msg "Compiler target mismatch: expected arm-none-eabi, got $result" M33_ENV err
        return 1
    fi

    export M33_TOOLCHAIN

    return 0
}

ddg_m33_status() {
    msg "M33 environment ready" M33_ENV ext
    msg "Target    : arm-none-eabi (Cortex-M33)" M33_ENV info
    msg "Toolchain : $M33_TOOLCHAIN" M33_ENV info
}

ddg_m33_env() {
    ddg_m33_project_root || return 1
    # Validate the new compiler before removing the old Linux environment.
    ddg_m33_prepare_toolchain || return 1
    ddg_m33_check_conflict || return 1
    ddg_env_prepend_path "$M33_TOOLCHAIN" || return 1

    export M33_CROSS_COMPILE="arm-none-eabi-"
    export DDG_ACTIVE_ENV="m33"

    ddg_m33_status
}

ddg_m33_env
