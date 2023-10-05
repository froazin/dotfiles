#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")"

[ "$1" == "--force" -o "$1" == "-f" ] && FORCE=true || FORCE=false

if ! $FORCE; then
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " reply
	echo ""
	if ! [[ $reply =~ ^[Yy](es){0,1}$ ]]; then
		exit 0
	fi
fi

function get_shells() {
    local shells=()
    [ -x "$(command -v bash)" ] && shells+=("bash")
    [ -x "$(command -v zsh)"  ] && shells+=("zsh")
    [ -x "$(command -v pwsh)" ] && shells+=("pwsh")

    echo "${shells[@]}"
}

function install_packages() {
    local packages=$@
    local installed_packages=()
    local warnings=false

    for package in $packages; do
        if [[ $package == "" ]]; then
            continue
        fi

        pkg_required=$(echo $package | cut -d ':' -f 1)
        pkg_name=$(echo $package | cut -d ':' -f 2)

        if [[ ! $pkg_required =~ (required|optional) ]]; then
            return 1
        fi

        if [[ $pkg_name == "" ]]; then
            return 1
        fi

        if [ -x "$(command -v $pkg_name)" ]; then
            installed_packages+=($pkg_name)
            continue
        fi

        if ! [[ $pkg_required == "required" ]]; then
            continue
        fi

        cat "$(dirname "${BASH_SOURCE}")/$(echo $package | cut -d ':' -f 2)/install.sh" | bash -s $FORCE
        if [[ $? -eq 0 ]]; then
            installed_packages+=($pkg_name)
            continue
        fi

        warnings=true
    done

    echo "${installed_packages[@]}"

    if [[ $warnings == true ]]; then
        return 2
    else
        return 0
    fi
}

function main() {
    SHELLS=$(get_shells)

    if [[ ! ${SHELLS[0]} =~ "bash" ]]; then
        echo "ERROR: Bash is a required shell. Exiting..."
        exit 1
    fi

    PACKAGES=$(cat requirements.txt)
    INSTALLED_PACKAGES=$(install_packages $PACKAGES)
    if [[ $? -eq 1 ]]; then
        echo "ERROR: Unrecoverable error in requirements.txt. Exiting..."
        exit 1
    fi

    if [[ $? -eq 2 ]]; then
        echo "WARNING: One or more required packages failed to install."
    fi

    for pkg in $INSTALLED_PACKAGES; do
        [ -f "$pkg/bootstrap.sh" ] && [ -r "$pkg/bootstrap.sh" ] && cat $pkg/bootstrap.sh | bash -s $FORCE
        if [[ $? -eq 1 ]]; then
            echo "ERROR: Encountered an unrecoverable error in $pkg/bootstrap.sh. Exiting..."
            exit 1
        fi

        if [[ $? -eq 2 ]]; then
            echo "WARNING: $pkg configuration bootstrap completed with warnings."
        fi
    done
}

main
unset main
