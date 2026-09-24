# Usage: msg "message" [context] [info|ext|wrn|err|crit]
# All levels use stdout. crit exits the current shell, including when sourced.
# Colors are enabled only for terminals; NO_COLOR disables them.
msg() {
    local message="${1:-}"
    local context="${2:--}"
    local level="${3:-info}"
    local label color="" reset="" bold="" normal="" line

    case "$level" in
        info) label="INFO"; color='\033[36m' ;;
        ext)  label="OK";   color='\033[32m' ;;
        wrn)  label="WARN"; color='\033[33m' ;;
        err)  label="ERR";  color='\033[31m' ;;
        crit) label="CRIT"; color='\033[31m' ;;
        *)    label="LOG" ;;
    esac

    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        reset='\033[0m'
        bold='\033[1m'
        normal='\033[22m'
    else
        color=""
    fi

    # Give every line a prefix; print message text literally, including backslashes.
    while IFS= read -r line; do
        printf '%b%b[%-4s]%b %-12s | %s%b\n' \
            "$color" "$bold" "$label" "$normal" "[$context]" "$line" "$reset"
    done <<< "$message"

    if [[ "$level" == "crit" ]]; then
        exit 1
    fi
    return 0
}


ddg_env_prepend_path() {
    # $1 toolchain path, not include bin
    local TOOLCHAIN=""
    TOOLCHAIN="${1:-}"

    if [[ -z "${TOOLCHAIN:-}" ]]; then
        return 1
    fi

    local tool_bin="$TOOLCHAIN/bin"

    case ":${PATH:-}:" in
        *":$tool_bin:"*)
            ;;  # 已存在，不重复添加
        *)
            export PATH="$tool_bin${PATH:+:$PATH}"
            ;;
    esac

    return 0
}
