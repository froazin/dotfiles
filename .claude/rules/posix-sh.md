---
paths:
  - "src/**/*.sh"
  - ".claude/**/*.sh"
---

# Installer scripts

- POSIX `sh` only (`#!/usr/bin/env sh`): no arrays, `[[ ]]`, `local`,
  `function`, `$'...'` or process substitution. Must pass plain `shellcheck`
  and `shfmt -d` (the PostToolUse hook runs both on edit). Their options live
  in `.shellcheckrc` and `.editorconfig`; never pass flags, because any shfmt
  formatting flag makes it ignore `.editorconfig`. Fix formatting with
  `shfmt -w <file>`: function braces on their own line, indented `case`
  arms, `> /dev/null` with a space.
- Log with `log <trace|debug|info|warning|error|fatal> "message"` from
  `src/internal/logging.sh`; paths in messages are wrapped as `<path>`.
  `fatal` exits.
- Functions report failure by returning non-zero, using the
  `cmd || { log error "..."; return 1; }` pattern, and collect errors in an
  `errors`/`failed` flag rather than stopping at the first one.
- Resolve repo files relative to `$(dirname "$0")`; module code is `eval`ed by
  `src/install.sh`, so `$0` is `install.sh`.
- Do not depend on `src/internal/github.sh` (jq, curl): `install.sh` does not
  source it.

## Installed Claude Code hooks

The `.sh` files in `src/modules/claude/templates/hooks/` are installed into
the Claude Code config directory and run there on their own, under Claude
Code, never under `install.sh`. The rules above for installer scripts don't
apply to them; these do.

- Don't source `logging.sh` or `common.sh`, and don't call `log`: neither is
  installed. A hook's stdout and stderr go to Claude, so print only what the
  hook contract asks for.
- `$0` is the installed hook, not `install.sh`. Resolve only files installed
  beside it, with `$(dirname "$0")`.
- Use shell builtins plus basic GNU utilities (coreutils, `sed`). Don't use
  `jq`, `python3`, `awk` or anything else a fresh install may lack, except
  through a wrapper that exits 0 when it's missing.
- Keep them fast: they run on every matched tool call. Prefer builtins to
  extra processes, such as `cd -P` and `$PWD` over `realpath`.
- Fail silent and off. Any error exits 0 with no output, and exit 2 only for
  the one thing the hook exists to block, because exit 2 blocks the tool. In
  `sh` a failed redirection on a special builtin such as `:` exits the
  script, so write files with `printf`.
