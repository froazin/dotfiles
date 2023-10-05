#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null       || exit 1
source .modules/common.sh 2> /dev/null        || exit 1
source .modules/devcontainers.sh 2> /dev/null || exit 1

check_requirements git rsync                  || exit 1

warnings=false

devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some git configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

write_log $INFO "Synchronizing git config."
rsync --exclude install.sh \
    --exclude bootstrap.sh \
    -avz --no-perms ./git/ $HOME > /dev/null 2>&1 || exit 1

if $devcontainer; then
    exit 2
fi

username=$(git config --global user.name)
email=$(git config --global user.email)

if ! [ -z "$username" ]; then
    write_log $DEBUG "Existing git configuration for global user.name <$username> was found."
    write_log $INFO "Persisting existing git configuration for global user.name"
    git config --global user.name "$username" || exit 1
fi

if ! [ -z "$email" ]; then
    write_log $DEBUG "Existing git configuration for global user.email <$email> was found."
    write_log $INFO "Persisting existing git configuration for global user.email"
    git config --global user.email "$email" || exit 1
fi

if $warnings; then
    exit 2
else
    exit 0
fi
