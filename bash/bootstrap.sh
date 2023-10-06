#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null       || exit 1
source .modules/common.sh 2> /dev/null        || exit 1
source .modules/devcontainers.sh 2> /dev/null || exit 1

check_requirements bash                       || exit 1

warnings=false
devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some bash configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

write_log $DEBUG "Copying bashrc file to <$HOME/.bashrc>."
cp -f bash/.bashrc $HOME/.bashrc || exit 1

write_log $DEBUG "Changing permissions of <$HOME/.bashrc> to 644."
chmod 644 $HOME/.bashrc || exit 1

if [ -f /etc/inputrc ]; then
    write_log $DEBUG "Copying inputrc file to <$HOME/.inputrc>."
    cp -f inputrc/.inputrc $HOME/.inputrc
    
    write_log $DEBUG "Adding bind command to <$HOME/.bashrc>."
    echo "bind -f ~/.inputrc" >> $HOME/.bashrc

    write_log $DEBUG "Changing permissions of <$HOME/.inputrc> to 644."
    chmod 644 $HOME/.inputrc
fi

if [ -x "$(command -v direnv)" ]; then
    write_log $DEBUG "Configuring direnv hooks for bash."
    cat << EOF >> $HOME/.bashrc
$(cat bash/direnv.sh)
EOF
fi

if [ -x "$(command -v ssh-agent)" ] && ! $devcontainer; then
    write_log $DEBUG "Configuring ssh-agent startup for bash."

    cat << EOF >> $HOME/.bashrc
$(cat bash/ssh.sh)
EOF
fi

if $warnings; then
    exit 2
else
    exit 0
fi
