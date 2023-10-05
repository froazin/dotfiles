#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")"

function bootstrap_packages() {
    local packages=()
    local errors=false
    local warnings=false

    write_log $DEBUG "Searching for configurations..."
    for dir in $(ls -d */); do
        pkg=$(echo $dir | cut -d '/' -f 1 | sed 's/\///g')
        write_log $DEBUG "Found package: $pkg"
        packages+=($pkg)
    done

    write_log $INFO "Bootstrapping configurations..."
    for package in $packages; do
        if [[ $package == "" ]]; then
            continue
        fi

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
    bootstrap_packages
    if [[ $? -eq 1 ]]; then
        write_log $ERROR "Bootstrapping completed with errors. Check $LOG_FILE for details."
    elif [[ $? -eq 2 ]]; then
        write_log $WARNING "Bootstrapping completed with warnings. Check $LOG_FILE for details."
    else
        write_log $INFO "Bootstrapping completed successfully."
    fi
}

for file in $(ls -f .private/*.sh); do
    source $file
done

main
unset main
