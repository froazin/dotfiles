#!/usr/bin/env zsh
# shellcheck shell=zsh

if (( $+commands[dircolors] )); then
  if [[ -r $HOME/.dircolors ]]; then
    eval "$(dircolors -b $HOME/.dircolors)"
  else
    eval "$(dircolors -b)"
  fi

  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

alias browse='xdg-open'

# Signal that a long-running command finished:  sleep 10; alert
alert() {
  local rc=$?
  local cmd=${history[$HISTCMD]:-$(fc -ln -1 2>/dev/null)}
  cmd=${cmd##[[:space:]]#}                       # trim leading blanks
  cmd=${cmd%%[;&|]##[[:space:]]#alert}           # drop trailing "; && || alert"
  cmd=${cmd%%[[:space:]]#}                       # trim trailing blanks

  print -n -- $'\a'                              # the bell
  if (( rc == 0 )); then
    print -P -- "%F{#2ace84}done%f ${cmd}"
  else
    print -P -- "%F{#e01b24}failed (${rc})%f ${cmd}"
  fi
}
