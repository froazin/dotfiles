#!/usr/bin/env zsh
# shellcheck shell=zsh
#
# Plugins, installed from system packages. No plugin manager.

# --- zsh-autosuggestions ----------------------------------------------------
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6a6a6a'   # the prompt's dim grey
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20             # don't suggest on huge pastes
ZSH_AUTOSUGGEST_MANUAL_REBIND=1                # skip a rebind on every prompt

# --- zsh-syntax-highlighting ------------------------------------------------
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Both plugins call is-at-least, which is part of zsh's autoloadable function
# tree (Debian: zsh-common) rather than the zsh binary. Sourcing them without it
# throws "is-at-least: function definition file not found" several times on
# every startup, so skip them entirely in that case - they cannot work properly
# anyway.
if zsh_have_function is-at-least; then
  for _zp in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
             /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    [[ -r $_zp ]] && source "$_zp"
  done
  unset _zp
fi
