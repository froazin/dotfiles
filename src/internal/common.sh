#!/usr/bin/env sh

check_commands()
{
    if [ $# -eq 0 ]; then
        log warning "No commands provided to check."
        return 0
    fi

    requirements="$*"
    failed='false'

    for req in $requirements; do
        command -v "$req" > /dev/null 2>&1 || {
            log error "Unable to find command: $req"

            failed='true'
        }
    done

    if [ "$failed" = 'true' ]; then
        return 1
    fi

    return 0
}

ensure_dir()
{
    [ -d "$1" ] || mkdir -p "$1" > /dev/null 2>&1 || {
        log error "Failed to create directory <$1>."
        return 1
    }
}

install_file()
{
    src="$1"
    dest="$2"

    if [ ! -f "$src" ]; then
        log error "Template not found: <$src>."
        return 1
    fi

    if [ -L "$dest" ]; then
        log warning "Existing file <$dest> is a symbolic link and will be left alone."
        return 1
    fi

    if [ -f "$dest" ]; then
        if cmp -s "$src" "$dest"; then
            log debug "<$dest> is already up to date."
            return 0
        fi

        log warning "Existing file <$dest> was found, it will be overwritten."
    fi

    ensure_dir "$(dirname "$dest")" || return 1

    cp --force "$src" "$dest" > /dev/null 2>&1 || {
        log error "Failed to write <$dest>."
        return 1
    }

    log debug "Installed <$dest>."
    return 0
}

get_distro_name()
{
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

is_devcontainer()
{
    [ "$REMOTE_CONTAINERS" = "true" ]
}

is_wsl()
{
    grep -q microsoft /proc/version > /dev/null 2>&1
}

is_root()
{
    [ "$(id -u)" -eq 0 ]
}
