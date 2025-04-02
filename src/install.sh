#!/usr/bin/env bash

eval "$(sdkmod logging)" || exit 1
eval "$(sdkmod common)" || exit 1

# Set the feature name for the logging package.
_FEATURE_NAME=dotfiles

function bootstrap_packages() {
    local packages=()
    local errors="false"

    log info "Bootstrapping dotfiles."

    log debug "Searching for configurations."
    for dir in "$(dirname "$0")/modules/"*; do
        local pkg

        pkg="$(basename "$dir")"
        packages+=("$pkg")

        log debug "Found configuration $pkg"
    done

    for package in "${packages[@]}"; do
        if [ -z "$package" ]; then
            continue
        fi

        if ! check_commands "$package"; then
            log debug "Skipping $package, as it is not installed."
            continue
        fi

        btstrpfile="$(dirname "$0")/modules/$package/bootstrap.sh"
        if [[ ! -f "$btstrpfile" ]]; then
            log debug "Bootstrap file for $package not found."
            continue
        fi

        log debug "Loading $package configuration from $btstrpfile."
        eval "$(cat "$btstrpfile")" >/dev/null 2>&1 || {
            log error "Failed to load $package configuration."
            errors="true"
            continue
        }

        log debug "Running $package configuration."
        bootstrap || {
            log error "Failed to execute $package configuration."
            errors="true"
        }

        # We should reset the bootstrap function to avoid running the same
        # function again if a package fails to implement the bootstrap function
        # or if the package is not a module.
        function bootstrap { true >/dev/null 2>&1; }
    done

    if $errors; then
        return 1
    fi

    log info "Dotfiles configuration completed successfully."
    return 0
}

function main() {
    bootstrap_packages || return 1
    return 0
}

main "$@" || {
    log warning "Dotfiles configuration has completed with errors."
    exit 1
}
