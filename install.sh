#!/usr/bin/env bash

REQUIRED_PACKAGES=(
    "bash"
    "cat"
    "ls"
    "sed"
    "cut"
    "dirname"
)

source internal/logging.sh 2> /dev/null      || exit 1
source internal/common.sh 2> /dev/null       || exit 1

check_requirements "${REQUIRED_PACKAGES[@]}" || exit 1

function bootstrap_packages() {
    local packages=()
    local errors=false
    local warnings=false

    write_log $INFO "Bootstrapping dotfiles."

    write_log $DEBUG "Searching for configurations."
    for dir in $(ls -d */); do
        local pkg=$(echo $dir | cut -d '/' -f 1 | sed 's/\///g')
        write_log $DEBUG "Found configuration: $pkg"
        local packages+=($pkg)
    done

    for package in "${packages[@]}"; do
        if [[ $package == "" ]]; then
            continue
        fi

        btstrpfile="$(dirname "${BASH_SOURCE}")/$(echo $package)/bootstrap.sh"
        if [[ ! -f "$btstrpfile" ]]; then
            write_log $DEBUG "Bootstrap file for $package not found."
            continue
        fi

        if [[ ! -x "$(command -v $package)" ]]; then
            write_log $DEBUG "$package is not installed. Skipping bootstrap."
            continue
        fi

        write_log $INFO "Configuring $package..."

        cat $btstrpfile | bash
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            local errors=true
        elif [[ $exit_code -eq 2 ]]; then
            local warnings=true
        fi
    done

    if $errors; then
        return 1
    elif $warnings; then
        return 2
    else
        return 0
    fi
}

function main() {
    cd "$(dirname "${BASH_SOURCE}")"

    bootstrap_packages
    local exit_code=$?
    if [[ $exit_code -eq 1 ]]; then
        write_log $ERROR "Bootstrapping dotfiles completed with errors. Check $LOG_FILE for details."
    elif [[ $exit_code -eq 2 ]]; then
        write_log $WARNING "Bootstrapping dotfiles completed with warnings. Check $LOG_FILE for details."
    else
        write_log $INFO "Bootstrapping dotfiles completed successfully."
    fi

    return 0
}

main
unset main
