#! /usr/bin/env bash

eval "$(sdkmod logging)" || exit 1
eval "$(sdkmod common)" || exit 1

function create_excludes_file {
    local excludes_file
    local excludes_file_line

    log info "Creating global gitignore file."
    excludes_file="$(git config --global core.excludesfile 2>/dev/null)" || {
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
    echo -e "# This is a generated file, manual changes may be lost.\n" >"$excludes_file" 2>/dev/null || {
        log error "Failed to create gitignore file at <$excludes_file>."
        return 1
    }

    while read -r excludes_file_line; do
        log debug "Adding <$excludes_file_line> to <$excludes_file>."

        echo "$excludes_file_line" >>"$excludes_file" 2>/dev/null
    done <"$(dirname "$0")/modules/git/templates/.gitignore" || {
        log error "Failed to add lines to gitignore file at <$excludes_file>."
        return 1
    }

    log debug "Setting git configuration for global core.excludesfile to <$excludes_file>."
    git config --global core.excludesfile "$excludes_file" >/dev/null 2>&1 || {
        log error "Failed to set git configuration for global core.excludesfile to <$excludes_file>."
        return 1
    }
}

function unset_gh_credential_helper {
    if [ -n "$(git config --global credential.https://github.com.helper)" ]; then
        log info "Unsetting gh cli git configuration for https://github.com.helper."

        git config --global --unset-all credential.https://github.com.helper >/dev/null 2>&1 || {
            log error "Failed to unset gh cli git configuration for https://github.com.helper."
            return 1
        }
    fi

    if [ -n "$(git config --global credential.https://gist.github.com.helper)" ]; then
        log info "Unsetting gh cli git configuration for https://gist.github.com.helper."

        git config --global --unset-all credential.https://gist.github.com.helper >/dev/null 2>&1 || {
            log error "Failed to unset gh cli git configuration for https://gist.github.com.helper."
            return 1
        }
    fi

    return 0
}

function unset_ssh_program {
    if [ -n "$(git config --global core.sshCommand)" ]; then
        log info "Unsetting ssh program git configuration."

        git config --global --unset-all core.sshCommand >/dev/null 2>&1 || {
            log error "Failed to unset ssh program git configuration."
            return 1
        }
    fi

    return 0
}

function bootstrap {
    local errors

    log info "Bootstrapping git configuration."

    create_excludes_file || {
        log error "Failed to create gitignore file."
        errors="true"
    }

    if is_devcontainer; then
        # If the gh cli credential helper is set on the host when using a devcontainer,
        # it will result in errors when trying to commit from within the devcontainer as
        # the gh cli will no longer be available. VSCode will automatically handle git
        # authentication for the devcontainer using the host configuration.
        unset_gh_credential_helper || {
            log error "Failed to unset gh cli git configuration."
            errors="true"
        }

        # VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
        # the ssh program git configuration to avoid conflicts.
        unset_ssh_program || {
            log error "Failed to unset ssh program git configuration."
            errors="true"
        }
    fi

    if [ -n "$errors" ]; then
        log warning "Git configuration completed with errors."
        return 1
    fi

    log info "Git configuration bootstrapped successfully."
    return 0
}
