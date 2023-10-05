#! /usr/bin/env bash

DEBUG=0
INFO=1
WARNING=2
ERROR=3
CRITICAL=4
FATAL=5

if [ -x "$(command -v tee)" ]; then
    LOG_FILE="$HOME/.dotfiles.log"

    if ! [ -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
else
    LOG_FILE=""
fi

function get_level_string() {
    local LEVEL=$1

    case $LEVEL in
        $DEBUG)
            echo "DEBUG"
            ;;
        $INFO)
            echo "INFO"
            ;;
        $WARNING)
            echo "WARNING"
            ;;
        $ERROR)
            echo "ERROR"
            ;;
        $CRITICAL)
            echo "CRITICAL"
            ;;
        $FATAL)
            echo "FATAL"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

function console_log() {
    local level=$1
    local msg=$2
    local timestamp=$3

    if [[ $level -lt $INFO ]]; then
        return 0
    fi

    local color=""

    case $level in
        $INFO)
            color='\033[1;36m'   # Cyan
            ;;
        $WARNING)
            color='\033[1;33m'   # Yellow
            ;;
        $ERROR)
            color='\033[1;31m'   # Red
            ;;
        $CRITICAL)
            color='\033[1;91m'   # Red
            ;;
        $FATAL)
            color='\033[1;91m'   # Red
            ;;
        *)
            color='\033[47m'     # White
            ;;
    esac

    local green='\033[0;32m' # Green
    local nc='\033[0m' # Text Reset

    echo -e "$green$timestamp $color[$(get_level_string $level)]$nc $msg"
    return 0
}

function write_log() {
    local level=$1
    local msg=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    if ! [[ $level =~ ^[0-9]+$ ]]; then
        console_log $ERROR "Invalid log level: $level" "$timestamp"
        return 1
    fi

    if [ -f "$LOG_FILE" ]; then
        tee -a "$LOG_FILE" <<< "{\"timestamp\":\"$timestamp\",\"level\":\"$(get_level_string $level)\",\"message\":\"$msg\"}" > /dev/null
    fi

    if [[ $level -eq $DEBUG ]]; then
        return 0
    fi

    console_log $level "$msg" "$timestamp"
    return 0
}

if [[ $LOG_FILE == "" ]]; then
    write_log $WARNING "Logging to file is disabled. tee is not installed."
fi 
