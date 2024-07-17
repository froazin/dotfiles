#! /usr/bin/env bash

source internal/logging.sh 2> /dev/null       || exit 1
source internal/common.sh 2> /dev/null        || exit 1
source internal/devcontainers.sh 2> /dev/null || exit 1

check_requirements git                        || exit 1

warnings=false

devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some git configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

function bootstrap_gitignore() {
    excludesfile=$(git config --global core.excludesfile)

    if [ -L "$excludesfile" ]; then
        write_log $WARNING "Existing git configuration for global core.excludesfile <$excludesfile> was found, but it is a symbolic link and will be ignored."
        return 2
    fi

    if [ -f "$excludesfile" ]; then
        write_log $WARNING "Existing git configuration for global core.excludesfile <$excludesfile> was found, but it will be overwritten."
        warnings=true
    else
        write_log $DEBUG "No existing git configuration for global core.excludesfile was found will generate a new one at <$HOME/.gitignore>."
        excludesfile="$HOME/.gitignore"
    fi

    write_log $DEBUG "Copying .gitignore to <$excludesfile>."
    echo "" > $excludesfile
    while read -r line; do
        write_log $TRACE "Adding <$line> to <$excludesfile>."
        echo "$line" >> $excludesfile
    done < git/.gitignore || return 1
    
    write_log $DEBUG "Setting git configuration for global core.excludesfile to <$excludesfile>."
    git config --global core.excludesfile "$excludesfile" || return 1

    return 0
}

bootstrap_gitignore
exit_code=$?
if [ $exit_code -eq 0 ]; then
    write_log $DEBUG "Successfully bootstrapped gitignore global configuration."
elif [ $exit_code -eq 2 ]; then
    write_log $DEBUG "Skipping gitignore global configuration bootstrap."
    warnings=true
else
    write_log $ERROR "Failed to bootstrap gitignore global configuration."
    exit 1
fi

if $warnings; then
    exit 2
else
    exit 0
fi
