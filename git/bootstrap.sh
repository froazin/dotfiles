#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null       || exit 1
source .modules/common.sh 2> /dev/null        || exit 1
source .modules/devcontainers.sh 2> /dev/null || exit 1

check_requirements git                        || exit 1

warnings=false

devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some git configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

function bootstrap_gitglobal() {
    if $devcontainer; then
        write_log $DEBUG "Will not modify git global config because the script is running in a devcontainer."
        return 2
    fi

    configfile="$HOME/.gitconfig"
    
    if [ -h "$configfile" ]; then
        write_log $WARNING "Existing git global config file <$configfile> was found, but it is a symbolic link and will be ignored."
        return 2
    fi

    username=$(git config --global user.name)
    email=$(git config --global user.email)

    write_log $DEBUG "Copying git global config file to <$configfile>."
    cp -f git/.gitconfig $configfile || return 1

    write_log $DEBUG "Changing permissions of <$configfile> to 644."
    chmod 644 $configfile || return 1

    if ! [ -z "$username" ]; then
        write_log $DEBUG "Existing git configuration for global user.name <$username> was found."
        write_log $INFO "Persisting existing git configuration for global user.name"
        git config --global user.name "$username" || return 1
    fi

    if ! [ -z "$email" ]; then
        write_log $DEBUG "Existing git configuration for global user.email <$email> was found."
        write_log $INFO "Persisting existing git configuration for global user.email"
        git config --global user.email "$email" || return 1
    fi
}

function bootstrap_gitignore() {
    excludesfile=$(git config --global core.excludesfile)

    if [ -L "$excludesfile" ]; then
        write_log $DEBUG "Existing git configuration for global core.excludesfile <$excludesfile> was found, but it is a symbolic link and will be ignored."
        return 2
    fi

    if [ -f "$excludesfile" ]; then
        write_log $WARNING "Existing git configuration for global core.excludesfile <$excludesfile> was found, but it will be overwritten."
        warnings=true
    else
        write_log $DEBUG "No existing git configuration for global core.excludesfile was found will generate a new one at <$HOME/.gitignore_global>."
        excludesfile="$HOME/.gitignore_global"
    fi

    write_log $DEBUG "Streaming .gitignore_global to <$excludesfile>."
    echo "" > $excludesfile
    while read -r line; do
        write_log $TRACE "Adding <$line> to <$excludesfile>."
        echo "$line" >> $excludesfile
    done < git/.gitignore_global || return 1
    
    write_log $DEBUG "Setting git configuration for global core.excludesfile to <$excludesfile>."
    git config --global core.excludesfile "$excludesfile" || return 1

    return 0
}

bootstrap_gitglobal
exit_code=$?
if [ $exit_code -eq 0 ]; then
    write_log $DEBUG "Successfully bootstrapped git global configuration file."
elif [ $exit_code -eq 2 ]; then
    write_log $DEBUG "Skipping git global configuration file bootstrap."
    warnings=true
else
    write_log $ERROR "Failed to bootstrap git global configuration file."
    exit 1
fi

bootstrap_gitignore
exit_code=$?
if [ $exit_code -eq 0 ]; then
    write_log $DEBUG "Successfully bootstrapped git global ignore configuration."
elif [ $exit_code -eq 2 ]; then
    write_log $DEBUG "Skipping git global ignore configuration bootstrap."
    warnings=true
else
    write_log $ERROR "Failed to bootstrap git global ignore configuration."
    exit 1
fi

if $warnings; then
    exit 2
else
    exit 0
fi
