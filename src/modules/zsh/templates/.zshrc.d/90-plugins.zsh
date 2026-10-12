#!/usr/bin/env zsh
# Plugins, installed from system packages. No plugin manager.

# --- zsh-autosuggestions ----------------------------------------------------
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6a6a6a'   # the prompt's dim grey
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20             # don't suggest on huge pastes
ZSH_AUTOSUGGEST_MANUAL_REBIND=1                # skip a rebind on every prompt

# --- zsh-syntax-highlighting ------------------------------------------------
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

if zsh_have_function is-at-least; then
  for _zp in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
             /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    [[ -r $_zp ]] && source "$_zp"
  done
  unset _zp
fi
