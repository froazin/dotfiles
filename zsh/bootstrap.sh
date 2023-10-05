#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null       || exit 1
source .modules/common.sh 2> /dev/null        || exit 1
source .modules/devcontainers.sh 2> /dev/null || exit 1

check_requirements zsh                        || exit 1

if ! [ -f zsh/base.sh ]; then
    write_log $ERROR "Unable to find zsh/base.sh. zsh configuration will not be applied."
    exit 1
fi

warnings=false
devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some zsh configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

echo "#! /usr/bin/env zsh" > $HOME/.zshrc

cat << EOF >> $HOME/.zshrc
$(cat zsh/base.sh)
EOF

if [ -x "$(command -v direnv)" ]; then
    write_log $INFO "Configuring direnv hooks for zsh."
    cat << EOF >> $HOME/.zshrc
$(cat zsh/direnv.sh)
EOF
fi

if [ -x "$(command -v ssh-agent)" ] && ! $devcontainer; then
    write_log $INFO "Configuring ssh-agent startup for zsh."

    cat << EOF >> $HOME/.zshrc
$(cat zsh/ssh.sh)
EOF
fi

if $warnings; then
    exit 2
else
    exit 0
fi
