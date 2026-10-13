#!/usr/bin/env zsh

if (( $+commands[dircolors] )); then
  if [[ -r $HOME/.dircolors ]]; then
    eval "$(dircolors -b "$HOME/.dircolors")"
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
  cmd=${cmd##[[:space:]]#}
  cmd=${cmd%%[;&|]##[[:space:]]#alert}           # drop trailing "; && || alert"
  cmd=${cmd%%[[:space:]]#}

  print -n -- $'\a'                              # the bell
  # $cmd stays out of print -P: under prompt_subst it would run its $(...).
  if (( rc == 0 )); then
    print -Pn -- '%F{#2ace84}done%f '
  else
    print -Pn -- "%F{#e01b24}failed (${rc})%f "
  fi
  print -r -- "$cmd"
}
