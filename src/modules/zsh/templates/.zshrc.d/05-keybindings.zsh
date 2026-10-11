#!/usr/bin/env zsh
# shellcheck shell=bash
#
# Key bindings: emacs mode with Windows-style word editing.

bindkey -e

# ---------------------------------------------------------------------------
# Word boundaries: bash/readline semantics, not zsh's much greedier default.
# ---------------------------------------------------------------------------
if zsh_have_function select-word-style; then
  autoload -Uz select-word-style
  select-word-style bash
fi

if zsh_have_function backward-kill-word-match; then
  autoload -Uz backward-kill-word-match
  zle -N backward-kill-space-word backward-kill-word-match
  zstyle ':zle:backward-kill-space-word' word-style space
  bindkey '^W' backward-kill-space-word
fi

# ---------------------------------------------------------------------------
# Windows-style word deletion: Ctrl mirrors Alt.
#   Ctrl+Backspace / Alt+Backspace -> kill the word behind the cursor
#   Ctrl+Delete    / Alt+Delete    -> kill the word ahead of the cursor
# ---------------------------------------------------------------------------
bindkey '^H'        backward-kill-word   # Ctrl+Backspace (also ports ~/.inputrc)
bindkey '^[^?'      backward-kill-word   # Alt+Backspace
bindkey '^[^H'      backward-kill-word   # Alt+Backspace, alternate encoding
bindkey '^[[127;5u' backward-kill-word   # Ctrl+Backspace, CSI-u encoding
bindkey '^[[127;3u' backward-kill-word   # Alt+Backspace,  CSI-u encoding

bindkey '^?'        backward-delete-char # plain Backspace
bindkey '^[[3~'     delete-char          # Delete
bindkey '^[[3;5~'   kill-word            # Ctrl+Delete
bindkey '^[[3;3~'   kill-word            # Alt+Delete

# Word movement, same Windows convention.
bindkey '^[[1;5D'   backward-word        # Ctrl+Left
bindkey '^[[1;5C'   forward-word         # Ctrl+Right
bindkey '^[[1;3D'   backward-word        # Alt+Left
bindkey '^[[1;3C'   forward-word         # Alt+Right

# Home / End, both the xterm and the VT sequences.
bindkey '^[[H'      beginning-of-line
bindkey '^[[F'      end-of-line
bindkey '^[[1~'     beginning-of-line
bindkey '^[[4~'     end-of-line

# Edit the current command line in $EDITOR.
if zsh_have_function edit-command-line; then
  autoload -Uz edit-command-line
  zle -N edit-command-line
  bindkey '^X^E' edit-command-line
fi

# ---------------------------------------------------------------------------
# run-help: help for the command under the cursor (Alt+H).
#   `git commit` + Alt+H -> man git-commit
#   `setopt`     + Alt+H -> zsh's own help for the builtin
# ---------------------------------------------------------------------------
if zsh_have_function run-help; then
  unalias run-help 2>/dev/null
  autoload -Uz run-help run-help-git run-help-sudo run-help-ip run-help-openssl
  bindkey '^[h' run-help
fi
