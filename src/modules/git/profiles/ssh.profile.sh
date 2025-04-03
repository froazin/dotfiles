#! /usr/bin/env bash

eval "$(sdkmod logging)" || exit 1

_FEATURE_NAME="git.ssh"

# VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
# the ssh program to avoid conflicts.

if [ -n "$(git config --global core.sshCommand)" ]; then
    log debug "Unsetting ssh program git configuration."

    git config --global --unset-all core.sshCommand >/dev/null 2>&1 || {
        log error "Failed to unset ssh program git configuration."
        exit 1
    }
fi
