#!/usr/bin/env zsh
# Shell maintenance.

zshup() {
  emulate -L zsh

  # Single source of truth: the same registry 10-completion.zsh builds from, so
  # adding a tool there automatically makes it refreshable here.
  local name rc
  for name in ${(ko)ZSH_OPTIONAL_COMPLETIONS}; do
    zcache_completion -f "$name" "${ZSH_OPTIONAL_COMPLETIONS[$name]}" ${commands[$name]}
    rc=$?
    case $rc in
      0) print -r -- "  _${name}  regenerated" ;;
      2) print -r -- "  _${name}  skipped (not installed)" ;;
      3) print -r -- "  _${name}  FAILED to generate" ;;
      *) print -r -- "  _${name}  unchanged" ;;
    esac
  done

  if [[ -n $ZSH_COMPDUMP ]] && zsh_have_function compinit; then
    rm -f "$ZSH_COMPDUMP" "$ZSH_COMPDUMP.zwc"
    autoload -Uz compinit
    compinit -d "$ZSH_COMPDUMP"
    print -r -- "  compdump rebuilt (${ZSH_COMPDUMP/#$HOME/~})"
  fi

  print -r -- "  run \`exec zsh\` to reload"
}

alias zshreload='exec zsh'
