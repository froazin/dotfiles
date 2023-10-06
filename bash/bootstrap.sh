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

cp bash/.bashrc $HOME/.bashrc
chmod 644 $HOME/.bashrc

if [ -f /etc/inputrc ]; then
    cp bash/.inputrc $HOME/.inputrc
    echo "bind -f ~/.inputrc" >> $HOME/.bashrc
fi

chmod 644 $HOME/.inputrc && \
    write_log $DEBUG "Changed permissions of ~/.inputrc to 644" || \
    write_log $ERROR "Failed to change permissions of ~/.inputrc to 644"

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
