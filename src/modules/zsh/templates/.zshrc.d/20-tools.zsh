#!/usr/bin/env zsh

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
  export DIRENV_WARN_TIMEOUT=60s
fi

# fzf registers ZLE widgets, so it must load before zsh-syntax-highlighting
# (90-plugins.zsh).
if (( $+commands[fzf] )); then
  _fzf_version=$(fzf --version | cut -d' ' -f1)
  _fzf_major_version=$(echo "$_fzf_version" | cut -d. -f1)
  _fzf_minor_version=$(echo "$_fzf_version" | cut -d. -f2)

  if [[ $_fzf_major_version -eq 0 && $_fzf_minor_version -ge 48 ]]; then
    source <(fzf --zsh)
  else
    _fzf_key_bindings="/usr/share/doc/fzf/examples/key-bindings.zsh"
    _fzf_completion="/usr/share/doc/fzf/examples/completion.zsh"

    if [[ -f $_fzf_key_bindings ]]; then
      source "$_fzf_key_bindings"
    fi

    if [[ -f $_fzf_completion ]]; then
      source "$_fzf_completion"
    fi
  fi
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s $NVM_DIR/nvm.sh ]]; then
  source "$NVM_DIR/nvm.sh"

  if (( $+functions[compdef] )) && [[ -s $NVM_DIR/bash_completion ]]; then
    source "$NVM_DIR/bash_completion"
  fi
fi
