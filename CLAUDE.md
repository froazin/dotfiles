# Dotfiles

Public dotfiles for a zsh workstation on Ubuntu (WSL first). The cloud-init
config that builds the WSL instance and installs these dotfiles into it lives
in [froazin/wsl](https://github.com/froazin/wsl). People copy from this repo, so it must stay generic.

## Contents

1. [Layout](#layout)
1. [Ground rules](#ground-rules)
1. [Checks](#checks)
1. [Commits](#commits)

## Layout

Before you change a path, read the design doc in its row. The docs in `docs/`
describe the code on the same branch: update them in the same commit as a
change that makes them out of date.

| Path | What | Read first |
| ---- | ---- | ---------- |
| `src/install.sh` | Entry point. Runs each `src/modules/<name>/bootstrap.sh` whose `<name>` is a command on `PATH`. | [docs/installer.md](docs/installer.md) |
| `src/internal/` | Shared POSIX sh helpers: `logging.sh` (`log`), `common.sh` (`check_commands`, `install_file`, `is_wsl`, ...). | [docs/installer.md](docs/installer.md) |
| `src/modules/claude/` | `templates/` is installed as `~/.claude` (commit-signing guard and no-session-links hooks and rules; the `wow_marker.sh` hook, `wow-core.md` rule and `wow-*` skills, on where a `.wow` marker is); `settings.json` and `keybindings.json` are deep-merged in with jq. pytest tests in `tests/`. | [docs/claude/overview.md](docs/claude/overview.md), then [commit-signing-guard.md](docs/claude/commit-signing-guard.md), [no-session-links.md](docs/claude/no-session-links.md) or [ways-of-working.md](docs/claude/ways-of-working.md) for a hook, rule or skill |
| `src/modules/git/` | Global gitignore, sets `core.excludesfile`. | [docs/git-module.md](docs/git-module.md) |
| `src/modules/podman/` | Persistent `~/.config/containers/auth.json`, linked from `~/.docker/config.json`. | [docs/podman-module.md](docs/podman-module.md) |
| `src/modules/zsh/` | `~/.zshenv`, `~/.zshrc` and numbered `~/.zshrc.d/` drop-ins. | [docs/zsh/overview.md](docs/zsh/overview.md) |
| `docs/` | Design docs for engineers changing the code. | — |
| `.shellcheckrc`, `.editorconfig` | Lint and format settings for ShellCheck and shfmt. | — |
| `pyproject.toml`, `.python-version`, `pyrightconfig.json` | Python dev tooling (uv, ruff, pytest, pyright), development only: nothing installed needs it. | — |

Path-specific guidance lives in `.claude/rules/` and loads when those files
are touched.

## Ground rules

- **Never commit identifying data.** No real names, emails, usernames,
  signing keys, hostnames, or `/mnt/c/Users/<name>/` paths in any file. They
  go in the user's local config, or their private WSL meta-data. Use
  placeholders like `<you>` or `jdoe` in examples.
- **Dependencies are graded, never fatal.** A module is skipped only when its
  own command is missing. Soft dependencies log errors and fail the module, but
  the config is still installed. Optional dependencies only warn. Shell config
  guards every tool at runtime.
- **Keep the three dependency lists in sync** when adding a tool:
  `src/modules/*/bootstrap.sh`, the README dependency table, and `packages` in
  froazin/wsl's `src/Ubuntu-26.04.user-data`, which needs its own pull request.
- **Prefer native mechanisms** (zsh builtins, official
  installers run as the user so they can self-update) over custom glue.
- **Don't write outside the repo to test.** Use throwaway `HOME`s
  (`HOME=$(mktemp -d) sh src/install.sh`). Installing or unregistering WSL
  instances needs the user's go-ahead.

## Checks

```sh
shellcheck src/install.sh src/internal/*.sh src/modules/*/bootstrap.sh src/modules/claude/templates/hooks/*.sh .claude/hooks/*.sh
shfmt -d .
for f in src/modules/zsh/templates/.zshenv src/modules/zsh/templates/.zshrc src/modules/zsh/templates/.zshrc.d/*.zsh; do zsh -n "$f"; done
uv sync                                                    # dev tools; uses the system python3
uv run ruff format --check && uv run ruff check
uv run pyright
uv run pytest
HOME=$(mktemp -d) SHELL=/usr/bin/zsh sh src/install.sh     # end-to-end install into a scratch home
```

ShellCheck and shfmt read their options from `.shellcheckrc` and
`.editorconfig`, so run them without flags: any shfmt formatting flag (`-i`,
`-ci`, ...) makes it ignore `.editorconfig`. shfmt cannot parse zsh:
`.editorconfig` excludes the zsh templates when walking a directory, but
never name one explicitly.

pyright skips any path containing a dot-directory, which is why the claude
module's templates live directly in `templates/` rather than `templates/.claude/`.

A PostToolUse hook (`.claude/hooks/lint-shell.sh`) runs ShellCheck/shfmt on
edited `.sh` files and `zsh -n` on zsh files, and reports failures back.

## Commits

Conventional commits with a scope, matching history: `feat(zsh): ...`,
`fix(git): ...`, `feat(wsl): ...`, `chore: ...`; `!` marks breaking changes.
