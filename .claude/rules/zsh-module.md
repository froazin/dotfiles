---
paths:
  - "src/modules/zsh/**"
---

# zsh module

- Templates start with `#!/usr/bin/env zsh` and indent with 2 spaces. The
  only check is `zsh -n <file>`. ShellCheck does not support zsh, so
  `.shellcheckrc` disables SC1071/SC1103 and it skips them silently. Never
  run shfmt on them: it detects them by shebang and mangles zsh syntax
  (`(( $+commands[x] ))` becomes `(($ + commands[x]))`).
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
  list in `src/wsl/Ubuntu-26.04.user-data` if it comes from apt.
- The installer never runs `chsh`; it only reports the login shell.
- Root gets its own copy of these files (and zsh as its login shell on WSL),
  and reaches them via `sudo su`/`sudo -s` with the user's repos under
  `$SUDO_HOME`. Check `EUID` for anything that must not run as root, such as
  launching Windows GUI editors or running `git status` in repos root does
  not own, and don't trust `$SHELL` to name the running shell.
