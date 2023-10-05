#! /usr/bin/env bash

source .modules/logging.sh 2> /dev/null       || exit 1
source .modules/common.sh 2> /dev/null        || exit 1
source .modules/devcontainers.sh 2> /dev/null || exit 1

check_requirements bash                       || exit 1

if ! [ -f bash/base.sh ]; then
    write_log $ERROR "Unable to find bash/base.sh. bash configuration will not be applied."
    exit 1
fi

warnings=false
devcontainer=false
if check_devcontainer; then
    write_log $WARNING "Some bash configurations will not be applied because the script is running in a devcontainer."
    devcontainer=true
    warnings=true
fi

echo "#! /usr/bin/env bash" > $HOME/.bashrc

cat << EOF >> $HOME/.bashrc
$(cat bash/base.sh)
EOF

if [ -x "$(command -v direnv)" ]; then
    write_log $INFO "Configuring direnv hooks for bash."
    cat << EOF >> $HOME/.bashrc
$(cat bash/direnv.sh)
EOF
fi

if [ -x "$(command -v ssh-agent)" ] && ! $devcontainer; then
    write_log $INFO "Configuring ssh-agent startup for bash."

    cat << EOF >> $HOME/.bashrc
$(cat bash/ssh.sh)
EOF
fi

if $warnings; then
    exit 2
else
    exit 0
fi
