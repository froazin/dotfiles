#!/usr/bin/env sh

. "$(dirname "$0")/internal/logging.sh" || exit 1
. "$(dirname "$0")/internal/common.sh" || exit 1

main()
{
    # Not "errors": modules are eval'ed into this shell and reset their own.
    install_errors="false"

    log info "Bootstrapping dotfiles."

    log debug "Searching for configurations."
    for dir in "$(dirname "$0")/modules/"*; do
        package="$(basename "$dir")"
        log debug "Found configuration $package"

        if ! command -v "$package" > /dev/null 2>&1; then
            log debug "Skipping $package, as it is not installed."
            continue
        fi

        btstrpfile="$dir/bootstrap.sh"
        if [ ! -f "$btstrpfile" ]; then
            log debug "Bootstrap file for $package not found."
            continue
        fi

        log debug "Loading $package configuration from $btstrpfile."
        eval "$(cat "$btstrpfile")" > /dev/null 2>&1 || {
            log error "Failed to load $package configuration."
            install_errors="true"
            continue
        }

        log debug "Running $package configuration."
        # shellcheck disable=SC2218 # The bootstrap function is defined in the package's bootstrap.sh file.
        bootstrap || {
            log error "Failed to execute $package configuration."
            install_errors="true"
        }

        # Reset, so a module without bootstrap() does not rerun this one.
        bootstrap()
        {
            true > /dev/null 2>&1
        }
    done

    if [ "$install_errors" = "true" ]; then
        return 1
    fi

    log info "Dotfiles configuration completed successfully."
    return 0
}

main "$@" || {
    log warning "Dotfiles configuration has completed with errors."
    exit 1
}
