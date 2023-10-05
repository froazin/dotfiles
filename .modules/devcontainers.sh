#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null || exit 1

function check_devcontainer() {
    # Check if the script is running in a devcontainer.
    # if it is, return 0, otherwise return 1.

    write_log $DEBUG "Checking for devcontainer."
    if [ -f /.dockerenv ]; then
        write_log $DEBUG "Devcontainer detected."
        return 0
    fi

    write_log $DEBUG "Devcontainer not detected."
    return 1
}
