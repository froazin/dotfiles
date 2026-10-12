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
