#! /usr/bin/env bash

eval "$(sdkmod logging)" || exit 1

_FEATURE_NAME="git.gpg"

# VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
# the gpg ssh program to avoid conflicts.

if [ -n "$(git config --global gpg.ssh.program)" ]; then
    log debug "Unsetting ssh program git configuration."

    git config --global --unset-all gpg.ssh.program >/dev/null 2>&1 || {
        log error "Failed to unset ssh program git configuration."
        exit 1
    }
fi
