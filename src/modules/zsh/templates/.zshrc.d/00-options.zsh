#!/usr/bin/env zsh

setopt extended_glob          # (#qN.mh+24)-style qualifiers, ^ and ~ patterns
setopt nomatch
setopt no_beep                # Windows Terminal turns the bell into a taskbar flash
setopt interactive_comments
setopt no_flow_control        # free up ^S / ^Q
setopt long_list_jobs
unsetopt autocd
unsetopt bg_nice              # older WSL kernels failed nice() on background jobs

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

# History is per session and in memory only: nothing is ever written to disk.
HISTSIZE=50000
SAVEHIST=0
unset HISTFILE

setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt hist_verify

unsetopt share_history
unsetopt inc_append_history
unsetopt append_history
unsetopt extended_history
