---
paths:
  - "src/**/*.sh"
  - ".claude/**/*.sh"
---

# Installer scripts

- POSIX `sh` only (`#!/usr/bin/env sh`): no arrays, `[[ ]]`, `local`,
  `function`, `$'...'` or process substitution. Must pass
  `shellcheck -s sh -e SC1091` and `shfmt -i 4` (the PostToolUse hook runs
  both on edit).
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
