#!/usr/bin/env zsh

skip_global_compinit=1

typeset -U path fpath

# Root of the <host>/<owner>/<repo> clones; Claude Code hooks and ws read it.
export WORKSPACE_DIR=${WORKSPACE_DIR:-${SUDO_HOME:-$HOME}/workspaces}

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

# No VS Code for root outside a dev container (where it runs as root itself):
# sudo drops the WSL variables `code` relies on, and the VS Code server runs as
# the user, so it could not save root's files anyway.
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

# The prompt renders the virtualenv name itself.
export VIRTUAL_ENV_DISABLE_PROMPT=1
