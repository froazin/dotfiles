#!/usr/bin/env sh

create_excludes_file() {
    log info "Configuring global gitignore file."
    excludes_file="$(git config --global core.excludesfile 2>/dev/null | sed "s/~/\$HOME/")" || {
        log debug "No existing git configuration for global core.excludesfile was found."
        return 0
    }

    if [ -L "$excludes_file" ]; then
        log warning "Existing git configuration for global core.excludesfile <$excludes_file> was found, but it is a symbolic link and will be ignored."
        return 1
    fi

    if [ -f "$excludes_file" ]; then
        log warning "Existing git configuration for global core.excludesfile <$excludes_file> was found, it will be overwritten."
    else
        log debug "No existing git configuration for global core.excludesfile was found a new one will be generated at <$HOME/.gitignore>."
        excludes_file="$HOME/.gitignore"
    fi

    log debug "Copying .gitignore to <$excludes_file>."
    cp --force "$(dirname "$0")/modules/git/templates/.gitignore" "$excludes_file" >/dev/null 2>&1 || {
        log error "Failed to create gitignore file at <$excludes_file>."
        return 1
    }

    log info "Global gitignore file created at <$excludes_file>."
    return 0
}

bootstrap() {
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
