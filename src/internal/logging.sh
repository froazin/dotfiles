#!/usr/bin/env sh

DOTFILES_LOG_LEVEL="${DOTFILES_LOG_LEVEL:-info}"
DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.local/var/log/dotfiles.log}"

_parse_level()
{
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        trace) echo 0 ;;
        debug) echo 1 ;;
        info) echo 2 ;;
        warning) echo 3 ;;
        error) echo 4 ;;
        fatal) echo 5 ;;
        *) echo 9 ;;
    esac
}

_get_level_string()
{
    case "$1" in
        0) echo TRACE ;;
        1) echo DEBUG ;;
        2) echo INFO ;;
        3) echo WARN ;;
        4) echo ERROR ;;
        5) echo FATAL ;;
        *) echo INVALID ;;
    esac
}

_log_to_console()
{
    if ! [ -t 1 ]; then
        return 0
    fi

    level=$1
    msg=$2
    timestamp=$3

    case "$level" in
        0) color='\033[1;30m' ;; # grey
        1) color='\033[1;33m' ;; # yellow
        2) color='\033[1;36m' ;; # cyan
        3) color='\033[1;33m' ;; # yellow
        4) color='\033[1;31m' ;; # red
        5) color='\033[1;91m' ;; # bright red
        *) return 1 ;;
    esac

    green='\033[0;32m'
    nc='\033[0m' # reset

    printf '%b%s %b[%s]%b %s\n' "$green" "$timestamp" "$color" "$(_get_level_string "$level")" "$nc" "$msg" 1>&2
    return 0
}

_log_to_file()
{
    level=$1
    msg=$2
    timestamp=$3

    # Not ensure_dir: its failure logs, which would recurse back here.
    [ -d "$(dirname "$DOTFILES_LOG_FILE")" ] || mkdir -p "$(dirname "$DOTFILES_LOG_FILE")" > /dev/null 2>&1 || return 1

    if ! [ -f "$DOTFILES_LOG_FILE" ]; then
        touch "$DOTFILES_LOG_FILE" > /dev/null 2>&1 || return 1
        chmod 644 "$DOTFILES_LOG_FILE" > /dev/null 2>&1
    fi

    if [ -f "$DOTFILES_LOG_FILE" ]; then
        printf '%s\n' "{\"timestamp\":\"$timestamp\",\"level\":\"$(_get_level_string "$level" | tr '[:upper:]' '[:lower:]')\",\"message\":\"$msg\"}" | tee -a "$DOTFILES_LOG_FILE" > /dev/null 2>&1
    fi

    return 0
}

log()
{
    timestamp=$(date --iso-8601=seconds)
    level="$(_parse_level "$1")"
    min_level="$(_parse_level "$DOTFILES_LOG_LEVEL")"

    shift 1
    msg="$*"

    if [ "$level" -lt "$min_level" ]; then
        return 0
    fi

    _log_to_console "$level" "$msg" "$timestamp" 1>&2

    # Fatal exits even when the log file cannot be written.
    if [ "$level" -ge 5 ]; then
        _log_to_file "$level" "$msg" "$timestamp"
        exit 1
    fi

    _log_to_file "$level" "$msg" "$timestamp"
}
