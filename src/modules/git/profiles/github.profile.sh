#! /usr/bin/env bash

# If the gh cli credential helper is set on the host when using a devcontainer,
# it will result in errors when trying to commit from within the devcontainer as
# the gh cli will no longer be available. VSCode will automatically handle git
# authentication for the devcontainer using the host configuration.

if [ -n "$(git config --global credential.https://github.com.helper)" ]; then
    git config --global --unset-all credential.https://github.com.helper >/dev/null 2>&1
fi

if [ -n "$(git config --global credential.https://gist.github.com.helper)" ]; then
    git config --global --unset-all credential.https://gist.github.com.helper >/dev/null 2>&1
fi
