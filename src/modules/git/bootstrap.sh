#!/usr/bin/env sh

create_excludes_file()
{
    log info "Configuring global gitignore file."
    # --get exits non-zero when the key is unset, which is not an error here.
    excludes_file="$(git config --global --get core.excludesfile 2> /dev/null)" || excludes_file=""

    case "$excludes_file" in
        \~/*)
            excludes_file="$HOME/${excludes_file#\~/}"
            ;;
    esac

    if [ -z "$excludes_file" ]; then
        excludes_file="$HOME/.gitignore"
        log debug "No existing git configuration for global core.excludesfile was found, a new one will be generated at <$excludes_file>."

        git config --global core.excludesfile "$excludes_file" > /dev/null 2>&1 || {
            log error "Failed to set global core.excludesfile to <$excludes_file>."
            return 1
        }
    fi

    if [ -L "$excludes_file" ]; then
        log warning "Existing git configuration for global core.excludesfile <$excludes_file> was found, but it is a symbolic link and will be ignored."
        return 1
    fi

    if [ -f "$excludes_file" ]; then
        log warning "Existing git configuration for global core.excludesfile <$excludes_file> was found, it will be overwritten."
    fi

    ensure_dir "$(dirname "$excludes_file")" || return 1

    log debug "Copying .gitignore to <$excludes_file>."
    cp --force "$(dirname "$0")/modules/git/templates/.gitignore" "$excludes_file" > /dev/null 2>&1 || {
        log error "Failed to create gitignore file at <$excludes_file>."
        return 1
    }

    log info "Global gitignore file created at <$excludes_file>."
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
