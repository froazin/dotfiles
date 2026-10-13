#!/usr/bin/env sh

create_excludes_file()
{
    log info "Configuring global gitignore file."
    # --get exits 1 when the key is unset, which is not an error here.
    excludes_file="$(git config --global --type=path --get core.excludesfile 2> /dev/null)" || [ $? -eq 1 ] || {
        log error "Failed to read global core.excludesfile."
        return 1
    }

    if [ -z "$excludes_file" ]; then
        excludes_file="$HOME/.gitignore"
        log debug "No existing git configuration for global core.excludesfile was found, a new one will be generated at <$excludes_file>."

        git config --global core.excludesfile "$excludes_file" > /dev/null 2>&1 || {
            log error "Failed to set global core.excludesfile to <$excludes_file>."
            return 1
        }
    fi

    install_file "$(dirname "$0")/modules/git/templates/.gitignore" "$excludes_file" || return 1

    log info "Global gitignore file installed at <$excludes_file>."
    return 0
}

bootstrap()
{
    errors=""

    log info "Bootstrapping git configuration."

    create_excludes_file || {
        log error "Failed to create gitignore file."
        errors="true"
    }

    if [ -n "$errors" ]; then
        log warning "Git configuration completed with errors."
        return 1
    fi

    log info "Git configuration bootstrapped successfully."
    return 0
}
