#!/bin/bash

# Source this file from Bash or Zsh. Capture its path before entering functions.
if [ -n "${ZSH_VERSION:-}" ]; then
    DDG_A35_SCRIPT_FILE="${(%):-%x}"
elif [ -n "${BASH_VERSION:-}" ]; then
    DDG_A35_SCRIPT_FILE="${BASH_SOURCE[0]}"
else
    printf '%s\n' "Please source this script from Bash or Zsh."
    return 1
fi

DDG_A35_SCRIPT_DIR="$(
    cd -- "$(dirname -- "$DDG_A35_SCRIPT_FILE")" && pwd -P
)" || return 1
unset DDG_A35_SCRIPT_FILE

source "$DDG_A35_SCRIPT_DIR/common.sh" || return 1

ddg_a35_project_root() {
    local proj_root

    proj_root="$(
        cd -- "$DDG_A35_SCRIPT_DIR/.." &&
        pwd -P
    )" || {
        msg "Cannot locate project root from: $DDG_A35_SCRIPT_DIR" A35_ENV err
        return 1
    }

    export DDG_PROJECT_ROOT="$proj_root"
}

# Run only after SDK loading succeeds; keep the user's M33_TOOLCHAIN selection.
ddg_a35_check_conflict() {
    if [[ "${DDG_ACTIVE_ENV:-}" != "m33" ]]; then
        return 0
    fi

    local m33_bin="${M33_TOOLCHAIN:-}/bin"
    local remaining="${PATH:-}" entry cleaned="" kept=0 more=0
    while :; do
        more=0
        case "$remaining" in
            *:*) entry="${remaining%%:*}"; remaining="${remaining#*:}"; more=1 ;;
            *) entry="$remaining" ;;
        esac
        if [[ -z "${M33_TOOLCHAIN:-}" || "$entry" != "$m33_bin" ]]; then
            if [[ "$kept" == 1 ]]; then
                cleaned="$cleaned:$entry"
            else
                cleaned="$entry"
                kept=1
            fi
        fi
        [[ "$more" == 1 ]] || break
    done
    export PATH="$cleaned"
    unset M33_CROSS_COMPILE DDG_ACTIVE_ENV || return 1
    msg "Previous M33 environment cleared; switching to A35." A35_ENV info
    return 0
}

# Keep SDK discovery, preflight, loading and verification together.
ddg_a35_prepare_sdk() {
    local sdk_root="${DDG_LINUX_SDK_ROOT:-$DDG_PROJECT_ROOT/openstlinux/sdk-installed}"
    sdk_root="$(cd -- "$sdk_root" && pwd -P)" || {
        msg "SDK directory not found: ${DDG_LINUX_SDK_ROOT:-$DDG_PROJECT_ROOT/openstlinux/sdk-installed}" A35_ENV err
        return 1
    }
    # Always derive this from the requested SDK; do not reuse a stale env-file path.
    local env_file="$sdk_root/environment-setup-cortexa35-ostl-linux"
    local native_root="$sdk_root/sysroots/x86_64-ostl_sdk-linux"
    local target_root="$sdk_root/sysroots/cortexa35-ostl-linux"
    local compiler="$native_root/usr/bin/aarch64-ostl-linux/aarch64-ostl-linux-gcc"
    local result version

    if [[ ! -f "$env_file" || ! -r "$env_file" ]]; then
        msg "SDK environment file missing or not readable: $env_file" A35_ENV err
        return 1
    fi
    if [[ ! -x "$compiler" || ! -d "$target_root" ]]; then
        msg "SDK compiler or target sysroot is missing: $sdk_root" A35_ENV err
        return 1
    fi
    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        msg "ST SDK requires LD_LIBRARY_PATH to be unset. Current environment retained." A35_ENV err
        return 1
    fi

    # Check in a subshell first; failed setup must not damage the active environment.
    if ! (
        source "$env_file" || exit 1
        [[ "${CROSS_COMPILE:-}" == "aarch64-ostl-linux-" &&
           "${SDKTARGETSYSROOT:-}" == "$target_root" &&
           "${OECORE_NATIVE_SYSROOT:-}" == "$native_root" &&
           -n "${CC:-}" ]] || exit 1
        result=$("$compiler" -dumpmachine) || exit 1
        [[ "$result" == "aarch64-ostl-linux" ]]
    ); then
        msg "SDK preflight failed; current environment retained: $sdk_root" A35_ENV err
        return 1
    fi

    # Reuse only a matching, active SDK whose compiler still resolves correctly.
    if [[ "${DDG_ACTIVE_ENV:-}" != "a35" ||
          "${DDG_A35_LOADED_SDK_ROOT:-}" != "$sdk_root" ||
          "${SDKTARGETSYSROOT:-}" != "$target_root" ||
          "${OECORE_NATIVE_SYSROOT:-}" != "$native_root" ||
          "${CROSS_COMPILE:-}" != "aarch64-ostl-linux-" ||
          -z "${CC:-}" ||
          "$(command -v aarch64-ostl-linux-gcc)" != "$compiler" ]]; then
        # Remove the old SDK's PATH entries before reloading, including partial loads.
        local old_native="${OECORE_NATIVE_SYSROOT:-$native_root}"
        local remaining="${PATH:-}" entry cleaned="" kept=0 more=0
        while :; do
            more=0
            case "$remaining" in
                *:*) entry="${remaining%%:*}"; remaining="${remaining#*:}"; more=1 ;;
                *) entry="$remaining" ;;
            esac
            case "$entry" in
                "$old_native"|"$old_native"/*|"$native_root"|"$native_root"/*) ;;
                *)
                    if [[ "$kept" == 1 ]]; then
                        cleaned="$cleaned:$entry"
                    else
                        cleaned="$entry"
                        kept=1
                    fi
                    ;;
            esac
            [[ "$more" == 1 ]] || break
        done
        # SDK certificate defaults must not point at an earlier SDK after switching.
        case "${SSL_CERT_FILE:-}" in "$old_native"/*) unset SSL_CERT_FILE ;; esac
        case "${SSL_CERT_DIR:-}" in "$old_native"/*) unset SSL_CERT_DIR ;; esac
        export PATH="$cleaned"
        source "$env_file" || {
            unset DDG_ACTIVE_ENV DDG_A35_LOADED_SDK_ROOT
            msg "Failed to load SDK environment: $env_file" A35_ENV err
            return 1
        }
    fi

    result=$("${CROSS_COMPILE}gcc" -dumpmachine) || return 1
    if [[ "$result" != "aarch64-ostl-linux" ||
          "${SDKTARGETSYSROOT:-}" != "$target_root" || -z "${CC:-}" ]]; then
        unset DDG_ACTIVE_ENV DDG_A35_LOADED_SDK_ROOT
        msg "Active compiler or sysroot does not match the requested SDK." A35_ENV err
        return 1
    fi
    version=$("$compiler" --version) || return 1
    DDG_A35_COMPILER_VERSION="${version%%$'\n'*}"
    export DDG_LINUX_SDK_ROOT="$sdk_root"
    export DDG_LINUX_ENV_FILE="$env_file"
    export DDG_LINUX_SOURCE_ROOT="${DDG_LINUX_SOURCE_ROOT:-$DDG_PROJECT_ROOT/openstlinux/sources/ostl-linux}"
    export DDG_A35_LOADED_SDK_ROOT="$sdk_root"
    return 0
}

ddg_a35_status() {
    msg "A35 environment ready" A35_ENV ext
    msg "Target    : aarch64-ostl-linux (Cortex-A35)" A35_ENV info
    msg "SDK       : $DDG_LINUX_SDK_ROOT" A35_ENV info
    msg "Compiler  : $DDG_A35_COMPILER_VERSION" A35_ENV info
}

ddg_a35_env() {
    ddg_a35_project_root || return 1
    # Load and verify the SDK before removing the old M33 environment.
    ddg_a35_prepare_sdk || return 1
    ddg_a35_check_conflict || return 1

    export DDG_ACTIVE_ENV="a35"

    ddg_a35_status
}

ddg_a35_env
