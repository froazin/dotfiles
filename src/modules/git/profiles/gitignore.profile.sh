#! /usr/bin/env bash

# Dotfiles are executed before vscode copies the gitconfig file to the container.
# This means that setting the excludes file in the main bootstrap.sh will
# prevent the hosts gitconfig from being copied to the container. As a workaround
# we set the excludes file here, which will be run when the user logs in to the
# container.

if [ -z "$(git config --global core.excludesfile 2>/dev/null)" ]; then
    git config --global core.excludesfile "$HOME/.gitignore" >/dev/null 2>&1
fi
