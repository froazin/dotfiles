#! /usr/bin/env bash

function create_excludes_file {
    local excludes_file

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

function ensure_user_profiles {
    local profile_dir

    profile_dir="$HOME/.profile.d"

    log debug "Ensureing user profile directory <$profile_dir> exists."

    if ! [ -d "$profile_dir" ]; then
        log info "Creating user profile directory <$profile_dir>."
        mkdir -p "$profile_dir" >/dev/null 2>&1 || {
            log error "Failed to create user profile directory <$profile_dir>."
            return 1
        }
    fi

    return 0
}

function create_profile {
    local profile_name
    local profile

    profile_name="$1"
    if [ -z "$profile_name" ]; then
        log error "No profile name provided."
        return 1
    fi

    profile="$(dirname "$0")/modules/git/profiles/$profile_name.profile.sh" || {
        log error "No profile found for <$profile_name>."
        return 1
    }

    ensure_user_profiles || {
        log error "Failed to ensure user profiles."
        return 1
    }

    log info "Creating profile <$profile_name>."
    cp --force "$profile" "$HOME/.profile.d/git-$profile_name.profile.sh" >/dev/null 2>&1 || {
        log error "Failed to copy profile <$profile_name>."
        return 1
    }

    log info "Profile <$profile_name> created successfully."
    return 0
}

function bootstrap {
    local errors
    local profiles

    profiles=()

    log info "Bootstrapping git configuration."

    create_excludes_file || {
        log error "Failed to create gitignore file."
        errors="true"
    }

    if is_devcontainer; then
        # Dotfiles are executed before the gitconfig is copied from the host to the
        # devcontainer, so we need to create a profile here to ensure that modifications
        # to the git configuration are applied after the host configuration is copied.

        profiles+=("gitconfig.devcontainers")
        for profile in "${profiles[@]}"; do
            create_profile "$profile" || {
                log error "Failed to create profile <$profile>."
                errors="true"
            }
        done
    fi

    if [ -n "$errors" ]; then
        log warning "Git configuration completed with errors."
        return 1
    fi

    log info "Git configuration bootstrapped successfully."
    return 0
}
