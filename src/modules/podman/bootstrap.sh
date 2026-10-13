#!/usr/bin/env sh

podman_create_auth_file()
{
    # podman login writes to $XDG_RUNTIME_DIR/containers/auth.json, which is
    # lost at logout. Credentials not found there are looked up in this
    # persistent file, which outlives the session.
    auth_file="$1"

    if [ -e "$auth_file" ] || [ -L "$auth_file" ]; then
        log debug "<$auth_file> already exists."
        return 0
    fi

    if ! [ -d "$(dirname "$auth_file")" ]; then
        mkdir -p "$(dirname "$auth_file")" > /dev/null 2>&1 || {
            log error "Failed to create directory <$(dirname "$auth_file")>."
            return 1
        }
    fi

    # Credentials, so owner-only, as podman login would create it.
    (umask 077 && printf '{\n\t"auths": {}\n}\n' > "$auth_file") > /dev/null 2>&1 || {
        log error "Failed to create <$auth_file>."
        return 1
    }

    log info "Created <$auth_file> for registry credentials."
    return 0
}

podman_link_docker_config()
{
    # Docker tooling, such as VS Code Dev Containers pulling private features,
    # reads credentials from the Docker config, so it gets podman's file.
    auth_file="$1"
    docker_dir="${DOCKER_CONFIG:-$HOME/.docker}"
    docker_config="$docker_dir/config.json"

    if [ -L "$docker_config" ]; then
        target="$(readlink "$docker_config")"

        if [ "$target" = "$auth_file" ]; then
            log debug "<$docker_config> already links to <$auth_file>."
            return 0
        fi

        log warning "<$docker_config> links to <$target> rather than <$auth_file> and will be left alone, so Docker tooling such as VS Code Dev Containers will not see podman's registry credentials."
        return 1
    fi

    if [ -e "$docker_config" ]; then
        log warning "<$docker_config> already exists and will be left alone, so Docker tooling such as VS Code Dev Containers will not see podman's registry credentials. Move its \"auths\" into <$auth_file>, remove it and run the install again."
        return 1
    fi

    if ! [ -d "$docker_dir" ]; then
        (umask 077 && mkdir -p "$docker_dir") > /dev/null 2>&1 || {
            log error "Failed to create directory <$docker_dir>."
            return 1
        }
    fi

    ln -s "$auth_file" "$docker_config" > /dev/null 2>&1 || {
        log error "Failed to link <$docker_config> to <$auth_file>."
        return 1
    }

    log info "Linked <$docker_config> to <$auth_file>."
    return 0
}

bootstrap()
{
    errors=""
    # Where podman looks after $XDG_RUNTIME_DIR/containers/auth.json.
    podman_auth_file="${XDG_CONFIG_HOME:-$HOME/.config}/containers/auth.json"

    log info "Bootstrapping podman configuration."

    podman_create_auth_file "$podman_auth_file" || {
        log error "Failed to create the persistent registry credentials file."
        errors="true"
    }

    podman_link_docker_config "$podman_auth_file" || {
        log error "Failed to share registry credentials with Docker tooling."
        errors="true"
    }

    if [ -n "$errors" ]; then
        log warning "Podman configuration completed with errors."
        return 1
    fi

    log info "Podman configuration bootstrapped successfully."
    return 0
}
