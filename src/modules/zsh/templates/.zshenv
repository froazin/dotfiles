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

# Like podman-docker's /etc/profile.d script (zsh never reads it), but only
# while the socket listens and we own it. Root takes the system socket, never a
# user podman.socket from the user manager `sudo su` starts for it.
if [[ -z $DOCKER_HOST ]] && (( $+commands[podman] )); then
  if (( EUID == 0 )); then
    _podman_sock=/run/podman/podman.sock
  else
    _podman_sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/podman/podman.sock"
  fi
  if [[ -S $_podman_sock && -O $_podman_sock ]]; then
    export DOCKER_HOST="unix://$_podman_sock"
  fi
  unset _podman_sock
fi

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# The prompt renders the virtualenv name itself.
export VIRTUAL_ENV_DISABLE_PROMPT=1
