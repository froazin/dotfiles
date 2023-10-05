#!/usr/bin/env bash

REQUIRED_PACKAGES=(
    "bash"
    "cat"
    "ls"
    "sed"
    "cut"
    "dirname"
)

source .modules/logging.sh 2> /dev/null      || exit 1
source .modules/common.sh 2> /dev/null       || exit 1

check_requirements "${REQUIRED_PACKAGES[@]}" || exit 1

function bootstrap_packages() {
    local packages=()
    local errors=false
    local warnings=false

    write_log $DEBUG "Searching for configurations."
    for dir in $(ls -d */); do
        pkg=$(echo $dir | cut -d '/' -f 1 | sed 's/\///g')
        write_log $DEBUG "Found configuration: $pkg"
        packages+=($pkg)
    done

    for package in "${packages[@]}"; do
        if [[ $package == "" ]]; then
            continue
        fi

        if [[ ! -x "$(command -v $package)" ]]; then
            write_log $DEBUG "$package is not installed. Skipping bootstrap."
            continue
        fi

        write_log $INFO "Bootstrapping $package."

        cat "$(dirname "${BASH_SOURCE}")/$(echo $package)/bootstrap.sh" | bash
        if [[ $? -eq 1 ]]; then
            errors=true
        elif [[ $? -eq 2 ]]; then
            warnings=true
        fi
    done

    if [[ $errors == true ]]; then
        return 1
    elif [[ $warnings == true ]]; then
        return 2
    else
        return 0
    fi
}

function main() {
    cd "$(dirname "${BASH_SOURCE}")"

    bootstrap_packages
    if [[ $? -eq 1 ]]; then
        write_log $ERROR "Bootstrapping completed with errors. Check $LOG_FILE for details."
    elif [[ $? -eq 2 ]]; then
        write_log $WARNING "Bootstrapping completed with warnings. Check $LOG_FILE for details."
    else
        write_log $INFO "Bootstrapping completed successfully."
    fi

    return 0
}

main
unset main
