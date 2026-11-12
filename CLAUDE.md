# Dotfiles

Public dotfiles for a zsh workstation on Ubuntu (WSL first), and for
PowerShell 7 on Windows. The cloud-init
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
| `src/install.sh` | Entry point on Linux. Runs each `src/modules/<name>/bootstrap.sh` whose `<name>` is a command on `PATH`, and defines the helpers they call: `log`, `ensure_dir`, `install_file`, `is_root`. | [docs/installer.md](docs/installer.md) |
| `src/install.ps1` | Entry point on Windows, the twin of `install.sh`. Runs each `src/modules/<name>/bootstrap.ps1` the same way, skipping modules without one, and defines `Write-DotfilesLog`, `Initialize-Directory` and `Install-File`. | [docs/installer.md](docs/installer.md) |
| `src/modules/claude/` | `templates/` is installed as `~/.claude` (commit-signing guard and no-session-links hooks and rules; the `wow_marker.sh` hook, `wow-core.md` rule and `wow-*` skills, on where a `.wow` marker is); `settings.json` and `keybindings.json` are deep-merged in with jq. On Windows, `bootstrap.ps1` lays `windows/` over the templates: a PowerShell twin of the ways-of-working hook, registered from `windows/settings.json`, and Windows copies of the commit-signing and no-session-links rules, without their hooks. It merges without jq. pytest and Pester tests in `tests/`. | [docs/claude/overview.md](docs/claude/overview.md), then [commit-signing-guard.md](docs/claude/commit-signing-guard.md), [no-session-links.md](docs/claude/no-session-links.md) or [ways-of-working.md](docs/claude/ways-of-working.md) for a hook, rule or skill |
| `src/modules/git/` | Global gitignore, sets `core.excludesfile`. Linux and Windows. | [docs/git-module.md](docs/git-module.md) |
| `src/modules/pwsh/` | Windows only: the PowerShell 7 `profile.ps1` and its numbered `profile.d/` drop-ins (prompt, PSReadLine, completion, direnv, `ws`), loaded in interactive sessions only. | [docs/pwsh-module.md](docs/pwsh-module.md) |
| `src/modules/podman/` | Persistent `~/.config/containers/auth.json`, linked from `~/.docker/config.json`. | [docs/podman-module.md](docs/podman-module.md) |
| `src/modules/zsh/` | `~/.zshenv`, `~/.zshrc` and numbered `~/.zshrc.d/` drop-ins. | [docs/zsh/overview.md](docs/zsh/overview.md) |
| `docs/` | Design docs for engineers changing the code. | — |
| `.github/workflows/ci.yml` | Runs the checks below on each pull request, and when the release workflow calls it. On a pull request only, then Claude's code review. | [docs/ci.md](docs/ci.md) |
| `REVIEW.md` | Instructions for CI's Claude code review: what counts as Important, the Nit cap, what to skip, what to always check and the evidence a finding needs. | [docs/ci.md](docs/ci.md#code-review) |
| `.github/workflows/release.yml`, `.cz.toml` | On a push to `main` that changes `src/`, calls CI, then releases each change that bumps the version, tagged `vX.Y.Z`, with the version commitizen works out. | [docs/releases.md](docs/releases.md) |
| `.shellcheckrc`, `.editorconfig` | Lint and format settings for ShellCheck and shfmt. | — |
| `PSScriptAnalyzerSettings.psd1` | Lint and format settings for PowerShell, read by CI and the VS Code PowerShell extension. | — |
| `.gitattributes` | LF line endings in every checkout, whatever `core.autocrlf` says, so bash can run the hooks. | — |
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
  froazin/wsl's `src/99-dotfiles.user-data`, which needs its own pull request.
  That user-data installs apt packages without their recommends, so list any
  recommend a module needs too. A Windows dependency goes in the module's
  `bootstrap.ps1` and the README's Windows table instead.
- **Keep the twins in step.** `install.sh` and `install.ps1`, and a module's
  `bootstrap.sh` and `bootstrap.ps1`, behave the same way; so do each POSIX
  hook and its PowerShell twin. Change both, or say in the docs why they
  differ.
- **Prefer native mechanisms** (zsh builtins, official
  installers run as the user so they can self-update) over custom glue.
- **Don't write outside the repo to test.** Use throwaway `HOME`s
  (`HOME=$(mktemp -d) sh src/install.sh`). On Windows set both `USERPROFILE`
  and `HOME`, and check `pwsh -NoProfile -c '$PROFILE.CurrentUserAllHosts'`
  lands in it before running `install.ps1`: the Documents folder usually
  follows `USERPROFILE`, but a redirected one may not. Installing or
  unregistering WSL instances needs the user's go-ahead.

## Checks

```sh
shellcheck src/install.sh src/modules/*/bootstrap.sh src/modules/claude/templates/hooks/*.sh .claude/hooks/*.sh
shfmt -d .
for f in src/modules/zsh/templates/.zshenv src/modules/zsh/templates/.zshrc src/modules/zsh/templates/.zshrc.d/*.zsh; do zsh -n "$f"; done
uv sync                                                    # dev tools; uses the system python3
uv run ruff format --check && uv run ruff check
uv run pyright
uv run pytest
HOME=$(mktemp -d) SHELL=/usr/bin/zsh sh src/install.sh     # end-to-end install into a scratch home
```

On Windows, in pwsh (CI's `windows` job runs the same):

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path src                                    # Pester 5; also run it in powershell.exe
$env:USERPROFILE = $env:HOME = (New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) (New-Guid))).FullName
pwsh -NoProfile -File src/install.ps1                      # then again with powershell.exe -ExecutionPolicy Bypass
```

ShellCheck and shfmt read their options from `.shellcheckrc` and
`.editorconfig`, so run them without flags: any shfmt formatting flag (`-i`,
`-ci`, ...) makes it ignore `.editorconfig`. shfmt cannot parse zsh:
`.editorconfig` excludes the zsh templates when walking a directory, but
never name one explicitly.

pyright skips any path containing a dot-directory, which is why the claude
module's templates live directly in `templates/` rather than `templates/.claude/`.

A PostToolUse hook (`.claude/hooks/lint-shell.sh`) runs ShellCheck/shfmt on
edited `.sh` files, `zsh -n` on zsh files, and PowerShell's parser (plus
PSScriptAnalyzer, when it's installed) on `.ps1` and `.psd1` files, and
reports failures back. It reads its input with `python3`, so it does nothing
without one.

## Commits

Conventional commits with a scope, matching history: `feat(zsh): ...`,
`fix(git): ...`, `feat(wsl): ...`, `chore: ...`; `!` marks breaking changes.

Squash-merge a pull request once CI passes, or didn't run because it only
changes docs, and every review thread is resolved. Resolve a thread only
after fixing what it raises, or replying with why it isn't a problem. When
you review a change locally, follow `REVIEW.md` as it is on `main`
(`git show origin/main:REVIEW.md`), not a copy the change edits.

A pull request's squash-merged title and description decide the next
release's version, so choose its type by what it changes. Releases start at
`v0.1.0`, and only the release workflow tags them. See
[docs/releases.md](docs/releases.md#how-the-version-is-decided).
