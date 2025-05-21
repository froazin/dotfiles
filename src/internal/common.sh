#! /usr/bin/env bash

function check_commands() {
    # Check if the required packages are installed and available in the path.
    # if any are missing, return 1, otherwise return 0.
    local requirements
    local failed

    if [[ $# -eq 0 ]]; then
        log warning "No commands provided to check."
        return 0
    fi

    requirements=("$@")
    failed='false'

    for req in "${requirements[@]}"; do
        command -v "$req" >/dev/null 2>&1 || {
            log error "Unable to find command: $req"

            failed='true'
        }
    done

    if [[ $failed == 'true' ]]; then
        return 1
    fi

    return 0
}

function get_distro_name {
    # Get the distribution name from /etc/os-release.
    # Supported distributions are: debian, ubuntu, alpine, redhat, centos, fedora.
    # If the distribution is not supported, return 1.
    local distro

    if ! [ -f /etc/os-release ]; then
        log error "Unsupported distribution."
        return 1
    fi

    distro="$(grep '^ID=' /etc/os-release | cut -d '=' -f 2 | tr -d '"')" || {
        log error "Failed to get distribution name."
        return 1
    }

    case "$distro" in
    debian | ubuntu | alpine)
        echo "$distro"
        return 0
        ;;
    redhat | centos | fedora)
        echo "redhat"
        return 0
        ;;
    *)
        log error "Unsupported distribution: $distro"
        return 1
        ;;
    esac
}

function is_devcontainer {
    # Check if the script is running in a devcontainer.

    [[ "$REMOTE_CONTAINERS" == "true" ]] && return 0 || return 1
}

function is_wsl {
    # Check if the script is running in wsl.

    grep -q microsoft /proc/version >/dev/null 2>&1 && return 0 || return 1
}

function is_root {
    # Check if the script is running as root.

    [[ "$(id -u)" -eq 0 ]] && return 0 || return 1
}
