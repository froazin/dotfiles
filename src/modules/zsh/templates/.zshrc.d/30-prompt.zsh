#!/usr/bin/env zsh
# Native zsh port of the devcontainers "common-utils" prompt theme
#
# Upstream:
#   github.com/devcontainers/features -> src/common-utils/scripts/devcontainers.zsh-theme
#
#   PROMPT="%{$fg[green]%}${prompt_username} %(?:%{$reset_color%}: :%{$fg_bold[red]%}: )"
#   PROMPT+='%{$fg_bold[blue]%}%(5~|%-1~/.../%3~|%4~)%{$reset_color%} '
#   PROMPT+='`inline git: (branch) in bold-cyan parens, branch bold-red, " X" bold-yellow if dirty`'
#   PROMPT+='%{$fg[white]%}$ %{$reset_color%}'
#
# Renders as:
#
#     user -> ~ $                                  home, no repo
#     user -> infra (main) $                       repo, clean
#     user -> infra (main X) $                     dirty, in an opted-in repo
#     user -> infra (a12a46f) $                    detached HEAD
#     user -> infra (main|rebase-i) $              mid-rebase
#     (infra)  user -> infra (main) $              virtualenv active
#     user@web01 -> infra (main) $                 over SSH
#     root -> /etc #                               as root: grey logo, # not $

setopt prompt_subst

# vcs_info supplies the whole git segment. Without it (Debian: zsh-common
# missing) the prompt still renders - it just never shows branch or dirty state.
if zsh_have_function vcs_info; then
  autoload -Uz vcs_info
  ZSH_VCS_INFO_OK=1
else
  ZSH_VCS_INFO_OK=0
fi
zmodload -F zsh/stat b:zstat 2>/dev/null

# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------
_zp_user='#2ace84'      # old theme green   username
_zp_ok='#CCCCCC'        # $reset_color      arrow ok, trailing $, venv
_zp_err='#E74856'       # $fg_bold[red]     arrow on failure, branch name
_zp_path='#21bfd3'      # old theme cyan    path
_zp_paren='#6a6a6a'     # old theme grey    parens around the branch
_zp_yellow='#F9F1A5'    # $fg_bold[yellow]  dirty marker
_zp_blue='#E95420'      # Ubuntu logo orange
_zp_dim='#767676'       # Campbell bright black, for the logo when root

# ---------------------------------------------------------------------------
# glyphs
# ---------------------------------------------------------------------------

_zp_logo=$'\uf31b'         # nf-linux-ubuntu
_zp_arrow=$'\u279c'        # heavy round-tipped rightwards arrow
_zp_dirty=$'\u2717'        # ballot X

# ---------------------------------------------------------------------------
# vcs_info
# ---------------------------------------------------------------------------
zstyle ':vcs_info:*'    enable git
zstyle ':vcs_info:*'    disable-patterns '/mnt(|/*)'   # never stall on a 9p mount
zstyle ':vcs_info:git*' check-for-changes false
zstyle ':vcs_info:git*' formats       '%b%m'
zstyle ':vcs_info:git*' actionformats '%b|%a%m'
zstyle ':vcs_info:git*+set-message:*' hooks git-detached git-dirty

# Resolve the real git directory for the repo vcs_info just found. Handles
# linked worktrees and submodules, where .git is a file rather than a directory.
_zp_gitdir() {
  local dir=${hook_com[base]}/.git
  if [[ -d $dir ]]; then
    print -r -- $dir
  elif [[ -f $dir ]]; then
    command git rev-parse --git-common-dir 2>/dev/null
  fi
}

# Upstream derives the branch as `git symbolic-ref --short HEAD` falling back to
# `git rev-parse --short HEAD`.
+vi-git-detached() {
  # Skip while a rebase/merge/bisect is in progress.
  [[ -n ${hook_com[action]} ]] && return 0

  local gitdir head
  gitdir=$(_zp_gitdir) || return 0
  [[ -r $gitdir/HEAD ]] || return 0
  head=$(<$gitdir/HEAD)
  [[ $head == ref:* ]] && return 0
  hook_com[branch]=${head[1,7]}
}

# ---------------------------------------------------------------------------
# Per-repo configuration, cached.
#
#   git config zsh-theme.show-dirty 1     show the dirty marker in this repo
#   git config zsh-theme.hide-status 1    suppress the git segment entirely
# ---------------------------------------------------------------------------
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

# The marker sits INSIDE the parens, so the colour has to return to the paren
# colour before the closing ")" that _zp_precmd appends.
+vi-git-dirty() {
  # Reclaim %m. zsh's git backend fills it with rebase patch progress -
  # "<40-char sha> # <subject> # empty (1 applied)" - which is a wall of noise
  # beside the %a action we already show. Cleared unconditionally, before any
  # early return below, so it never leaks into the prompt.
  hook_com[misc]=''

  _zp_repo_cfg "$(_zp_gitdir)" || return 0

  if (( _zp_cfg_hide_status )); then
    hook_com[branch]=''
    hook_com[misc]=''
    return 0
  fi

  (( _zp_cfg_show_dirty )) || return 0

  [[ -n $(command git status --porcelain --ignore-submodules=dirty 2>/dev/null) ]] &&
    hook_com[misc]+=" %F{${_zp_yellow}}${_zp_dirty}%f%F{${_zp_paren}}"
}

# ---------------------------------------------------------------------------
# Variable segments are assembled in precmd, not inline in PROMPT.
# ---------------------------------------------------------------------------
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

# SSH marker. Whether this is an SSH session cannot change mid-shell, so it is
# resolved once here; %m is expanded at render time by prompt_subst.
if [[ -n $SSH_CONNECTION || -n $SSH_CLIENT || -n $SSH_TTY ]]; then
  _zp_host='@%m'
else
  _zp_host=''
fi

# ---------------------------------------------------------------------------
# The prompt.
# ---------------------------------------------------------------------------
PROMPT=''
PROMPT+='${_zp_venv}'                                              # (venv)
PROMPT+="%(!.%F{${_zp_dim}}.%F{${_zp_blue}})${_zp_logo} %f"      # logo, grey as root
PROMPT+="%F{${_zp_user}}%n\${_zp_host}%f "                         # user[@host]
PROMPT+="%(?.%F{${_zp_ok}}.%F{${_zp_err}})${_zp_arrow}%f "         # arrow, red on failure
PROMPT+="%F{${_zp_path}}%1~%f "                                    # cwd basename
PROMPT+='${_zp_git}'                                               # (branch[ X])
PROMPT+="%F{${_zp_ok}}%(!.#.\$)%f "                                # $, or # as root

RPROMPT=''

# ---------------------------------------------------------------------------
# Terminal title.
# ---------------------------------------------------------------------------
if [[ $TERM != (dumb|linux|) ]]; then
  _zp_title()         { print -Pn -- "\e]0;%n@%m: $1\a" }
  _zp_title_preexec() { _zp_title "$1" }
  _zp_title_precmd()  { _zp_title "${SHELL:t}" }
  add-zsh-hook preexec _zp_title_preexec
  add-zsh-hook precmd  _zp_title_precmd
fi
