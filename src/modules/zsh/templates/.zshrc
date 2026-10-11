#!/usr/bin/env zsh
# shellcheck shell=bash
#
# This file is a loader and nothing else. Every actual setting lives in a
# numbered file under ~/.zshrc.d/.
#
# Load order matters and is encoded in the filenames:
#   00 options       shell options + history
#   05 keybindings   emacs mode, word-editing keys, run-help
#   10 completion    fpath, cached tool completions, compinit, zstyles
#   20 tools         direnv, fzf          (both register ZLE widgets)
#   30 prompt        native oh-my-posh replica via vcs_info
#   40 aliases
#   50 functions     ws / workspace / wsc
#   60 maintenance   zshup
#   90 plugins       autosuggestions, then syntax-highlighting DEAD LAST
#
# $HOME is used explicitly rather than ~ or $ZDOTDIR: VS Code's shell
# integration relocates $ZDOTDIR to a temporary directory and sources this file
# from there, so anything $ZDOTDIR-relative would break in the VS Code terminal.

for _rc in $HOME/.zshrc.d/*.zsh(N); do
  source "$_rc"
done
unset _rc
