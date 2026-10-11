#!/usr/bin/env zsh
# shellcheck shell=bash
#
# Shell options and history policy.

setopt extended_glob          # (#qN.mh+24)-style qualifiers, ^ and ~ patterns
setopt nomatch                # error on a glob with no matches, don't pass it through
setopt no_beep                # Windows Terminal turns the bell into a taskbar flash
setopt interactive_comments   # allow # comments when typing interactively
setopt no_flow_control        # free up ^S / ^Q
setopt long_list_jobs
unsetopt autocd               # `cd` must be explicit (matches the old bootstrap)
unsetopt bg_nice              # older WSL kernels failed nice() on background jobs

# ---------------------------------------------------------------------------
# Capability probing.
# ---------------------------------------------------------------------------
zsh_have_function() {
  local -a _f
  _f=( ${^fpath}/$1(N) )
  (( $#_f ))
}

if zsh_have_function add-zsh-hook; then
  autoload -Uz add-zsh-hook
else
  add-zsh-hook() {
    local hook=$1 fn=$2
    case $hook in
      precmd)  (( ${precmd_functions[(I)$fn]} ))  || precmd_functions+=($fn)  ;;
      preexec) (( ${preexec_functions[(I)$fn]} )) || preexec_functions+=($fn) ;;
      chpwd)   (( ${chpwd_functions[(I)$fn]} ))   || chpwd_functions+=($fn)   ;;
      *)       return 1 ;;
    esac
  }
fi

# ---------------------------------------------------------------------------
# History: in-memory, for THIS SESSION ONLY. Nothing is ever written to disk.
# ---------------------------------------------------------------------------
HISTSIZE=50000
SAVEHIST=0
unset HISTFILE

setopt hist_ignore_space      # a leading space keeps a command out of history
setopt hist_ignore_all_dups   # a repeat removes the older occurrence
setopt hist_reduce_blanks
setopt hist_verify            # !! expands onto the line for review, doesn't run

unsetopt share_history        # nothing to share - there is no file
unsetopt inc_append_history
unsetopt append_history
unsetopt extended_history
