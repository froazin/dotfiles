#!/usr/bin/env zsh

zshup() {
  emulate -L zsh

  local name
  for name in ${(ko)ZSH_OPTIONAL_COMPLETIONS}; do
    zcache_completion -f "$name" "${ZSH_OPTIONAL_COMPLETIONS[$name]}" "${commands[$name]}"
    case $? in
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
