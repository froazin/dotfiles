---
paths:
  - "src/modules/zsh/**"
---

# zsh module

- Templates are zsh but start with `# shellcheck shell=bash` so editors lint
  them. Bash-mode ShellCheck cannot parse zsh syntax and reports errors on
  valid code; the real check is `zsh -n <file>`.
- `.zshrc` only loads `~/.zshrc.d/*.zsh`; load order is the numeric prefix.
  Keep a setting in the file whose topic it belongs to. Anything registering
  ZLE widgets loads before `90-plugins.zsh` (zsh-syntax-highlighting).
- Every integration is guarded at runtime and silently does nothing when its
  tool is missing: `(( $+commands[tool] ))` for commands, a file test for
  sourced tools (e.g. nvm via `$NVM_DIR/nvm.sh`). A missing tool must never
  print on shell startup.
- Generated completions go through the `ZSH_OPTIONAL_COMPLETIONS` registry in
  `10-completion.zsh`; `zshup` iterates the same registry.
- `compinit` runs in `10-completion.zsh`. Anything that would call it itself
  (e.g. bash completions) loads after that and only if `compdef` exists.
- When a template starts depending on a new tool, update all three:
  the dependency lists in `bootstrap.sh` (soft vs optional; sourced tools go
  in `ZSH_OPTIONAL_SOURCED`), the README dependency table, and the package
  list in `src/wsl/ubuntu.user-data` if it comes from apt.
- The installer never runs `chsh`; it only reports the login shell.
