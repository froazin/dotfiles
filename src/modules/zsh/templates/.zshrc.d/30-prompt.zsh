#!/usr/bin/env zsh
# Native zsh port of the devcontainers "common-utils" prompt theme:
# github.com/devcontainers/features -> src/common-utils/scripts/devcontainers.zsh-theme

setopt prompt_subst

# Without vcs_info (zsh-common missing) the prompt just has no git segment.
if zsh_have_function vcs_info; then
  autoload -Uz vcs_info
  ZSH_VCS_INFO_OK=1
else
  ZSH_VCS_INFO_OK=0
fi
zmodload -F zsh/stat b:zstat 2>/dev/null

_zp_user='#2ace84'      # old theme green   username
_zp_ok='#CCCCCC'        # $reset_color      arrow ok, trailing $, venv
_zp_err='#E74856'       # $fg_bold[red]     arrow on failure, branch name
_zp_path='#21bfd3'      # old theme cyan    path
_zp_paren='#6a6a6a'     # old theme grey    parens around the branch
_zp_yellow='#F9F1A5'    # $fg_bold[yellow]  dirty marker
_zp_orange='#E95420'    # Ubuntu logo orange
_zp_dim='#767676'       # Campbell bright black, for the logo when root

_zp_logo=$'\uf31b'         # nf-linux-ubuntu
_zp_arrow=$'\u279c'        # heavy round-tipped rightwards arrow
_zp_dirty=$'\u2717'        # ballot X

zstyle ':vcs_info:*'    enable git
zstyle ':vcs_info:*'    disable-patterns '/mnt(|/*)'   # never stall on a 9p mount
zstyle ':vcs_info:git*' check-for-changes false
zstyle ':vcs_info:git*' formats       '%b%m'
zstyle ':vcs_info:git*' actionformats '%b|%a%m'
zstyle ':vcs_info:git*+set-message:*' hooks git-detached git-dirty

# .git is a file, not a directory, in linked worktrees and submodules.
_zp_gitdir() {
  local dir=${hook_com[base]}/.git
  if [[ -d $dir ]]; then
    print -r -- $dir
  elif [[ -f $dir ]]; then
    command git rev-parse --git-common-dir 2>/dev/null
  fi
}

# Show a detached HEAD as the short sha like upstream, not vcs_info's
# describe/name-rev name (e.g. main~2).
+vi-git-detached() {
  # Mid-rebase HEAD is detached, but vcs_info already names the branch being rebased.
  [[ -n ${hook_com[action]} ]] && return 0

  local gitdir head
  gitdir=$(_zp_gitdir) || return 0
  [[ -r $gitdir/HEAD ]] || return 0
  head=$(<$gitdir/HEAD)
  [[ $head == ref:* ]] && return 0
  hook_com[branch]=${head[1,7]}
}

# Per-repo opt-ins, cached on the config file's mtime:
#   git config zsh-theme.show-dirty 1     show the dirty marker in this repo
#   git config zsh-theme.hide-status 1    suppress the git segment entirely
typeset -g _zp_cfg_gitdir=''
typeset -g _zp_cfg_mtime=''
typeset -g _zp_cfg_show_dirty=0
typeset -g _zp_cfg_hide_status=0

_zp_repo_cfg() {
  local gitdir=$1
  [[ -n $gitdir ]] || return 1

  local -a st
  zstat -A st +mtime "$gitdir/config" 2>/dev/null || st=(0)

  if [[ $gitdir != $_zp_cfg_gitdir || $st[1] != $_zp_cfg_mtime ]]; then
    _zp_cfg_gitdir=$gitdir
    _zp_cfg_mtime=$st[1]
    _zp_cfg_show_dirty=0
    _zp_cfg_hide_status=0

    local line
    for line in ${(f)"$(command git config --get-regexp '^zsh-theme\.' 2>/dev/null)"}; do
      case $line in
        'zsh-theme.show-dirty 1')  _zp_cfg_show_dirty=1  ;;
        'zsh-theme.hide-status 1') _zp_cfg_hide_status=1 ;;
      esac
    done
  fi
  return 0
}

# The marker sits inside the parens, so it must switch back to the paren
# colour before the ")" that _zp_precmd appends.
+vi-git-dirty() {
  # zsh's git backend fills %m with rebase patch progress, which is noise
  # beside %a. Cleared before any early return so it never leaks through.
  hook_com[misc]=''

  _zp_repo_cfg "$(_zp_gitdir)" || return 0

  if (( _zp_cfg_hide_status )); then
    hook_com[branch]=''
    return 0
  fi

  (( _zp_cfg_show_dirty )) || return 0

  # `git status` can run repo-configured programs (core.fsmonitor, filters),
  # so as root only in repos root owns; the branch still shows elsewhere.
  (( EUID == 0 )) && [[ ! -O $_zp_cfg_gitdir ]] && return 0

  [[ -n $(command git status --porcelain --ignore-submodules=dirty 2>/dev/null) ]] &&
    hook_com[misc]+=" %F{${_zp_yellow}}${_zp_dirty}%f%F{${_zp_paren}}"
}

_zp_venv=''
_zp_git=''

_zp_precmd() {
  (( ZSH_VCS_INFO_OK )) && vcs_info

  if [[ -n $VIRTUAL_ENV ]]; then
    local name=${VIRTUAL_ENV:t}
    [[ $name == (.venv|venv) ]] && name=${VIRTUAL_ENV:h:t}
    _zp_venv="%F{${_zp_ok}}(${name}) %f"
  else
    _zp_venv=''
  fi

  if [[ -n $vcs_info_msg_0_ ]]; then
    _zp_git="%F{${_zp_paren}}(%F{${_zp_err}}${vcs_info_msg_0_}%F{${_zp_paren}})%f "
  else
    _zp_git=''
  fi
}
add-zsh-hook precmd _zp_precmd

if [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY ]]; then
  _zp_host='@%m'
else
  _zp_host=''
fi

PROMPT=''
PROMPT+='${_zp_venv}'                                              # (venv)
PROMPT+="%(!.%F{${_zp_dim}}.%F{${_zp_orange}})${_zp_logo} %f"    # logo, grey as root
PROMPT+="%F{${_zp_user}}%n\${_zp_host}%f "                         # user[@host]
PROMPT+="%(?.%F{${_zp_ok}}.%F{${_zp_err}})${_zp_arrow}%f "         # arrow, red on failure
PROMPT+="%F{${_zp_path}}%1~%f "                                    # cwd basename
PROMPT+='${_zp_git}'                                               # (branch[ X])
PROMPT+="%F{${_zp_ok}}%(!.#.\$)%f "                                # $, or # as root

RPROMPT=''

if [[ $TERM != (dumb|linux|) ]]; then
  # Not print -P on the command line: under prompt_subst it would run any
  # $(...) in it. Control chars are blanked so they can't end the title early.
  _zp_title()         { print -rn -- $'\e]0;'"${(%):-%n@%m}: ${1//[[:cntrl:]]/ }"$'\a' }
  _zp_title_preexec() { _zp_title "$1" }
  # Not $SHELL: under `sudo -s` that is root's login shell, not this one.
  _zp_title_precmd()  { _zp_title "$ZSH_NAME" }
  add-zsh-hook preexec _zp_title_preexec
  add-zsh-hook precmd  _zp_title_precmd
fi
