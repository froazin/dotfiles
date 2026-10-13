#!/usr/bin/env zsh
# 90-plugins must stay last: zsh-syntax-highlighting has to follow every ZLE widget.

for _rc in $HOME/.zshrc.d/*.zsh(N); do
  source "$_rc"
done
unset _rc
