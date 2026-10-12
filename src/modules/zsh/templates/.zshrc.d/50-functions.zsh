#!/usr/bin/env zsh
# A workspace is a git repository under ~/workspaces, laid out as
# <provider>/<org>/<repo>, e.g. ~/workspaces/github.com/froazin/dotfiles
#
# `-c` prefers a *.code-workspace file at the workspace root over the plain
# directory, so a repo that defines a multi-root workspace opens as that
# workspace rather than as a bare folder.
#
# Under sudo, workspaces are looked up in the invoking user's home ($SUDO_HOME),
# so a root shell started with `sudo su` or `sudo -s` still finds them.

# Emit the list of workspaces, relative to the workspace root.
__ws_list() {
  emulate -L zsh
  local workspace_dir=${WORKSPACE_DIR:-${SUDO_HOME:-$HOME}/workspaces}
  [[ -d $workspace_dir ]] || return 1

  find "$workspace_dir" -mindepth 3 -maxdepth 3 -type d 2>/dev/null \
    | grep -E "^${workspace_dir}/[^/]+/[^/]+/[^/]+$" \
    | grep -v '\$RECYCLE\.BIN/' \
    | sed "s|^${workspace_dir}/||" \
    | sort
}

# Resolve what `code` should be pointed at for a given workspace directory.
__ws_code_target() {
  emulate -L zsh
  local dir=$1
  local -a candidates

  candidates=( $dir/*.code-workspace(N) )

  if (( ! $#candidates )); then
    print -r -- "$dir"
    return 1
  fi

  local preferred=$dir/${dir:t}.code-workspace
  if [[ -f $preferred ]]; then
    print -r -- "$preferred"
  else
    print -r -- "${candidates[1]}"
  fi
  return 0
}

workspaces() {
  emulate -L zsh

  local open_code=0
  while [[ $1 == -* ]]; do
    case $1 in
      -c|--code) open_code=1; shift ;;
      -h|--help)
        print -r -- 'usage: ws [-c|--code] [query]'
        print -r -- '  no query   pick a workspace with fzf'
        print -r -- '  query      jump straight there if it matches exactly one'
        print -r -- '  -c         also open the workspace in VS Code - a'
        print -r -- '             *.code-workspace file at its root if there is'
        print -r -- '             one, otherwise the directory itself'
        return 0 ;;
      --) shift; break ;;
      *)  print -ru2 -- "ws: unknown option: $1"; return 2 ;;
    esac
  done

  # `local -x` so the fzf preview subprocess can see it.
  local -x WS_DIR=${WORKSPACE_DIR:-${SUDO_HOME:-$HOME}/workspaces}
  local query="$*" target

  if [[ ! -d $WS_DIR ]]; then
    print -ru2 -- "The Workspaces directory does not exist. Please create it to use this function."
    return 1
  fi

  if ! (( $+commands[fzf] )); then
    print -ru2 -- "fzf is not installed. Please install it to use this function."
    return 1
  fi

  # --select-1 jumps straight there when the query matches exactly one
  # workspace; --exit-0 gives up quietly when it matches none.
  #
  # git can run programs a repo's config names (core.fsmonitor, gpg.program),
  # so as root the preview skips git in workspaces root does not own.
  target=$(
    __ws_list | fzf \
      --query="$query" \
      --select-1 --exit-0 \
      --height=80% --reverse \
      --prompt='workspace> ' \
      --preview='printf "%s\n\n" "$WS_DIR"/{}; \
                 [ "$(id -u)" -ne 0 ] || [ -O "$WS_DIR"/{} ] || exit 0; \
                 git -C "$WS_DIR"/{} status -sb 2>/dev/null; \
                 echo; \
                 git -C "$WS_DIR"/{} log --oneline -10 2>/dev/null' \
      --preview-window='right,55%,wrap'
  )

  if [[ -n $target && -d $WS_DIR/$target ]]; then
    cd -- "$WS_DIR/$target" || {
      print -ru2 -- "Failed to change directory to $WS_DIR/$target"
      return 1
    }
    if (( open_code )); then
      # Same rule as EDITOR in .zshenv: no VS Code for root outside a dev container.
      if (( EUID == 0 )) && [[ $REMOTE_CONTAINERS != true ]]; then
        print -ru2 -- "ws: not opening VS Code as root"
        return 1
      elif (( $+commands[code] )); then
        local code_target
        if code_target=$(__ws_code_target "$WS_DIR/$target"); then
          print -r -- "ws: opening ${code_target:t}"
        fi
        code "$code_target"
      else
        print -ru2 -- "ws: 'code' is not on PATH"
        return 1
      fi
    fi
  else
    print -ru2 -- "Invalid workspace selected or workspace does not exist."
    return 1
  fi
}

# Same thing, but always opens VS Code.
wsc() { workspaces -c "$@" }

alias workspace=workspaces
alias ws=workspaces

# --- completion -------------------------------------------------------------
_ws() {
  local context state line
  local -a ws_candidates
  ws_candidates=( ${(f)"$(__ws_list 2>/dev/null)"} )

  _arguments -C \
    '(-c --code)'{-c,--code}'[open in VS Code: its *.code-workspace file, else the directory]' \
    '(-h --help)'{-h,--help}'[show usage]' \
    '1:workspace:->workspace' && return 0

  case $state in
    workspace) _describe -t workspaces 'workspace' ws_candidates ;;
  esac
}

(( ${ZSH_COMPINIT_OK:-0} )) && compdef _ws workspaces workspace ws wsc
