#!/usr/bin/env zsh

skip_global_compinit=1

typeset -U path fpath

path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/.pulumi/bin"
  $path
  "/snap/bin" # normally added by /etc/profile.d/apps-bin-path.sh
)

# Snap desktop files - also normally handled by apps-bin-path.sh.
if [[ -d /var/lib/snapd/desktop ]]; then
  typeset -U -T XDG_DATA_DIRS xdg_data_dirs :
  export XDG_DATA_DIRS
  xdg_data_dirs=( ${xdg_data_dirs:-/usr/local/share /usr/share} /var/lib/snapd/desktop )
fi

# Prefer VS Code, but fall back so this file is still correct on a
# machine without it - it is seeded from dotfiles and has to work
# on servers and in containers too. Not for root, except in a dev container
# where VS Code itself runs as root: elsewhere sudo drops the WSL variables the
# code launcher relies on, and the VS Code server runs as the user, so it could
# not save root's files anyway.
if (( $+commands[code] )) && { (( EUID != 0 )) || [[ $REMOTE_CONTAINERS == true ]] }; then
  export EDITOR='code --wait'
elif (( $+commands[vim] )); then
  export EDITOR='vim'
else
  export EDITOR='vi'
fi
export VISUAL="$EDITOR"

# xdg-open's generic handler falls back to $BROWSER.
if [[ -x /usr/local/bin/start ]]; then
  export BROWSER=/usr/local/bin/start
elif [[ -x /mnt/c/Windows/explorer.exe ]]; then
  export BROWSER=/mnt/c/Windows/explorer.exe
fi

# Without this a non-root virsh talks to qemu:///session, which cannot see
# system VMs or the default NAT network.
export LIBVIRT_DEFAULT_URI='qemu:///system'

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# We render the virtualenv name ourselves in the prompt; stop activate scripts
# from prepending their own "(venv) " to PS1.
export VIRTUAL_ENV_DISABLE_PROMPT=1
