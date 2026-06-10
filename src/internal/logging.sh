#!/usr/bin/env sh

DOTFILES_LOG_LEVEL="${DOTFILES_LOG_LEVEL:-"info"}"
DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-"$HOME/.local/var/log/dotfiles.log"}"

_parse_level() {
    level=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    case "$level" in
    "trace")
        echo "0"
        ;;
    "debug")
        echo "1"
        ;;
    "info")
        echo "2"
        ;;
    "warning")
        echo "3"
        ;;
    "error")
        echo "4"
        ;;
    "fatal")
        echo "5"
        ;;
    *)
        echo "9"
        ;;
    esac
}

_get_level_string() {
    level=$1

    case "$level" in
    "0")
        echo "TRACE"
        ;;
    "1")
        echo "DEBUG"
        ;;
    "2")
        echo "INFO"
        ;;
    "3")
        echo "WARN"
        ;;
    "4")
        echo "ERROR"
        ;;
    "5")
        echo "FATAL"
        ;;
    *)
        echo "INVALID"
        ;;
    esac
}

_log_to_console() {
    if ! [ -t 1 ]; then
        # stdout is not a tty
        return 0
    fi

    color=''
    level=$1
    msg=$2
    timestamp=$3

    case "$level" in
    "0")
        color='\033[1;30m' # Grey
        ;;
    "1")
        color='\033[1;33m' # Yellow
        ;;
    "2")
        color='\033[1;36m' # Cyan
        ;;
    "3")
        color='\033[1;33m' # Yellow
        ;;
    "4")
        color='\033[1;31m' # Red
        ;;
    "5")
        color='\033[1;91m' # Red
        ;;
    *)
        return 1
        ;;
    esac

    green='\033[0;32m' # Green
    nc='\033[0m'       # Text Reset

    # shellcheck disable=SC1087
    printf '%b\n' "$green$timestamp $color[$(_get_level_string "$level")]$nc $msg" 1>&2
    return 0
}

log() {
    timestamp=$(date --iso-8601=seconds)
    level="$(_parse_level "$1")"
    min_level="$(_parse_level "$DOTFILES_LOG_LEVEL")"

    shift 1
    msg="$*"

    if ! echo "$level" | grep -Eq '^[0-9]+$'; then
        return 1
    fi

    if [ "$level" -lt "$min_level" ]; then
        return 0
    fi

    _log_to_console "$level" "$msg" "$timestamp" 1>&2

    if ! [ -d "$(dirname "$DOTFILES_LOG_FILE")" ]; then
        if ! mkdir -p "$(dirname "$DOTFILES_LOG_FILE")" >/dev/null 2>&1; then
            return 1
        fi
    fi

    if ! [ -f "$DOTFILES_LOG_FILE" ]; then
        if ! touch "$DOTFILES_LOG_FILE" >/dev/null 2>&1; then
            return 1
        fi

        chmod 644 "$DOTFILES_LOG_FILE" >/dev/null 2>&1
    fi

    if [ -f "$DOTFILES_LOG_FILE" ]; then
        printf '%s\n' "{\"timestamp\":\"$timestamp\",\"level\":\"$(_get_level_string "$level" | tr '[:upper:]' '[:lower:]')\",\"message\":\"$msg\"}" | tee -a "$DOTFILES_LOG_FILE" >/dev/null 2>&1
    fi

    if [ "$level" -ge 5 ]; then
        # Program should immediately exit if a fatal error occurs
        exit 1
    fi

    return 0
}
