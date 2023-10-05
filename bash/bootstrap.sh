#! /usr/bin/env bash

for file in $(ls -f .private/*.sh); do
    source $file
done

if ! [ -f bash/base.sh ]; then
    write_log $ERROR "Unable to find bash/base.sh. bash configuration will not be applied."
    exit 1
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

if [ -x "$(command -v ssh-agent)" ]; then
    write_log $INFO "Configuring ssh-agent startup for bash."

    cat << EOF >> $HOME/.bashrc
$(cat bash/ssh.sh)
EOF
fi
