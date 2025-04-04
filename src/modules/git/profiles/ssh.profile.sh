#! /usr/bin/env bash

# VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
# the ssh program to avoid conflicts.

if [ -n "$(git config --global core.sshCommand)" ]; then
    git config --global --unset-all core.sshCommand >/dev/null 2>&1
fi
