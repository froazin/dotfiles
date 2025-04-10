#! /bin/sh

# VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
# the gpg ssh program to avoid conflicts.

if [ -n "$(git config --global gpg.ssh.program)" ]; then
    git config --global --unset-all gpg.ssh.program >/dev/null 2>&1
fi
