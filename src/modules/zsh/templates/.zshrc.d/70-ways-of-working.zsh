#!/usr/bin/env zsh
# A ways-of-working repository holds shared working practices, and its
# user-config/ directory is copied into ~/.claude. Its clone URL is the first
# line of ~/.config/ways-of-working/repo, which the WSL user-data writes from
# the meta-data's ways_of_working. It is cloned to
# ~/workspaces/<host>/<owner>/<repo>, where ws finds it.

__wow_config=${XDG_CONFIG_HOME:-$HOME/.config}/ways-of-working/repo

# Sets reply=(url dir host) from the config, or fails without a usable URL:
# https://host/owner/repo, ssh://[user@]host/owner/repo or [user@]host:owner/repo.
__wow_target() {
  emulate -L zsh
  setopt extended_glob
  local url rest part
  local -a parts

  [[ -r $__wow_config ]] || return 1
  # Fails on a last line with no newline, but still sets url.
  read -r url < $__wow_config || [[ -n $url ]] || return 1

  if [[ $url == *://* ]]; then
    rest=${url#*://}
    # Drops any user and port from the host.
    rest=${${${rest%%/*}##*@}%%:*}/${rest#*/}
  elif [[ $url == [^/]##:* ]]; then
    rest=${${url%%:*}##*@}/${url#*:}
  else
    return 1
  fi

  parts=( ${(s:/:)${${rest%/}%.git}} )
  (( $#parts == 3 )) || return 1
  for part in $parts; do
    [[ $part == [A-Za-z0-9._-]## && $part != (.|..) ]] || return 1
  done

  reply=( $url ${WORKSPACE_DIR:-$HOME/workspaces}/${(j:/:)parts} $parts[1] )
}

# Clones the repository if it isn't there yet, asking gh to log in when it's a
# private GitHub repository, then copies its user-config/ into ~/.claude. Run
# it again to copy what changed after a pull.
wow-setup() {
  emulate -L zsh
  local claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  local config=${__wow_config/#$HOME/~}
  local retry="Open a new shell or run wow-setup to try again, or delete $config to stop."
  local url dir host err

  if ! __wow_target; then
    if [[ -r $__wow_config ]]; then
      print -ru2 -- "wow-setup: $config needs a clone URL ending in <host>/<owner>/<repo>, such as https://github.com/OWNER/REPO.git."
    else
      print -ru2 -- "wow-setup: no repository is configured. Put its clone URL in $config."
    fi
    return 1
  fi
  url=$reply[1] dir=$reply[2] host=$reply[3]

  if [[ ! -d $dir/.git ]]; then
    if [[ -e $dir ]]; then
      print -ru2 -- "wow-setup: ${dir/#$HOME/~} exists but isn't a git clone."
      return 1
    fi
    if ! (( $+commands[git] )); then
      print -ru2 -- "wow-setup: git is not installed."
      return 1
    fi

    print -r -- "wow-setup: cloning $url into ${dir/#$HOME/~}."
    # No prompts, so a private repository fails here instead of asking for a
    # password, and gh logs in for it below.
    if ! err=$(GIT_TERMINAL_PROMPT=0 git clone --quiet -- $url $dir 2>&1); then
      if [[ $url != https://* || $host != (github.com|${GH_HOST:-github.com}) ]] || ! (( $+commands[gh] )); then
        print -ru2 -- "$err"
        print -ru2 -- "wow-setup: failed to clone $url. $retry"
        return 1
      fi

      if ! gh auth status --hostname $host > /dev/null 2>&1; then
        print -r -- "wow-setup: log in to $host with gh to clone it."
        gh auth login --hostname $host --git-protocol https --web || {
          print -ru2 -- "wow-setup: gh did not log in. $retry"
          return 1
        }
      fi

      # gh passes its own credentials to git, whatever the git config says.
      gh repo clone $url $dir -- --quiet || {
        print -ru2 -- "wow-setup: failed to clone $url. $retry"
        return 1
      }
    fi
  fi

  if [[ ! -d $dir/user-config ]]; then
    print -ru2 -- "wow-setup: ${dir/#$HOME/~} has no user-config directory to copy."
    return 1
  fi

  # Owner-only, as the claude module creates it: it holds credentials too.
  if [[ ! -d $claude_dir ]]; then
    mkdir -p -m 700 -- $claude_dir || return 1
  fi
  cp -R -- $dir/user-config/. $claude_dir/ || {
    print -ru2 -- "wow-setup: failed to copy ${dir/#$HOME/~}/user-config into ${claude_dir/#$HOME/~}."
    return 1
  }

  print -r -- "wow-setup: copied ${dir/#$HOME/~}/user-config into ${claude_dir/#$HOME/~}."
}

__wow_first_login() {
  precmd_functions=( ${precmd_functions:#__wow_first_login} )
  wow-setup
}

# Until the clone exists, a shell with a terminal runs wow-setup before its
# first prompt, once .zshrc has loaded, so Ctrl-C can't cut startup short.
# Never as root, and never in VS Code's environment probe, which is an
# interactive shell with no terminal.
if (( EUID != 0 )) && [[ -t 0 && -t 1 && -r $__wow_config ]] && { ! __wow_target || [[ ! -d $reply[2]/.git ]] }; then
  add-zsh-hook precmd __wow_first_login
fi
