#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null || exit 1

function check_wsl() {
    # Check if the script is running in wsl.
    # if it is, return 0, otherwise return 1.

    write_log $DEBUG "Checking for WSL."
    if grep -q microsoft /proc/version; then
        write_log $DEBUG "WSL detected."
        return 0
    fi

    write_log $DEBUG "WSL not detected."
    return 1
}
