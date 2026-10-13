#!/usr/bin/env zsh

if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
  export DIRENV_WARN_TIMEOUT=60s
fi

# fzf registers ZLE widgets, so it must load before zsh-syntax-highlighting
# (90-plugins.zsh).
if (( $+commands[fzf] )); then
  _fzf_version=( ${(s:.:)${$(fzf --version)%% *}} )
  if (( _fzf_version[1] > 0 || _fzf_version[2] >= 48 )); then
    source <(fzf --zsh)
  else
    for _fzf_script in /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh; do
      [[ -f $_fzf_script ]] && source "$_fzf_script"
    done
  fi
  unset _fzf_version _fzf_script
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s $NVM_DIR/nvm.sh ]]; then
  source "$NVM_DIR/nvm.sh"

  if (( $+functions[compdef] )) && [[ -s $NVM_DIR/bash_completion ]]; then
    source "$NVM_DIR/bash_completion"
  fi
fi
