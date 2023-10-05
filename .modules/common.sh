#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null || exit 1

function check_requirements() {
    # Check if the required packages are installed and available in the path.
    # if any are missing, return 1, otherwise return 0.
    requirements=("$@")
    failed=false

    for req in "${requirements[@]}"; do
        write_log $DEBUG "Checking for required package $req."
        if ! [ -x "$(command -v $req)" ]; then
            write_log $ERROR "Unable to find required package $req."
            failed=true
        else
            write_log $DEBUG "Found required package $req."
        fi
    done

    if [[ $failed == true ]]; then
        return 1
    else
        return 0
    fi
}
