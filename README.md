# Dotfiles

Feel free to use and adapt these configurations for your own setup.

## Usage

```bash
# 1. Clone the repository
git clone https://github.com/froazin/dotfiles.git
cd dotfiles

# 2. Run the install script
chmod +x ./src/install.sh 
./src/install.sh
```

### Windows

On Windows, `src/install.ps1` is the installer, for PowerShell 7 (and Windows
PowerShell 5.1, which it also runs on). It sets up the `claude`, `git` and
`pwsh` modules, and skips the others:

```powershell
git clone https://github.com/froazin/dotfiles.git
cd dotfiles
pwsh -NoProfile -File .\src\install.ps1
```

From Windows PowerShell, whose default execution policy runs no scripts, use
`powershell -NoProfile -ExecutionPolicy Bypass -File .\src\install.ps1`. Like
`install.sh`, it logs to `~\.local\var\log\dotfiles.log`, and exits 1 when
anything needs your attention.

The PowerShell profile goes in `Documents\PowerShell`. If Windows Security's
Controlled folder access is on, it blocks that ("Protected folder access
blocked"). Rather than allowing PowerShell through for good, turn Controlled
folder access off (Windows Security > Virus & threat protection > Ransomware
protection), run the installer again, then turn it back on.

### Root

The installer configures whoever runs it. To keep `sudo su` and `sudo -i` in
zsh, make the system zsh (the one in `/etc/shells`, never one in your home)
root's login shell, then give root its own copy of the configuration:

```bash
sudo usermod -s /usr/bin/zsh root
sudo -H sh ./src/install.sh
```

`sudo -s` already starts your own shell, so it needs only the second line.
Root's files are copies rather than links to yours, so a process running as
you can't change what root runs. Run the install again after pulling changes.

If zsh is ever removed, set root back to bash first
(`sudo usermod -s /bin/bash root`), or `su` and `sudo -i` stop working. On WSL,
`wsl -u root -e /usr/sbin/usermod -s /bin/bash root` recovers it from Windows.

## Modules

Each directory under `src/modules/` is a module with a `bootstrap.sh` that
defines a `bootstrap()` function, a `bootstrap.ps1` that defines
`Invoke-Bootstrap` for Windows, or both. A module is skipped entirely unless a
command matching its directory name is on `PATH`.

| Module | Installs |
| ------ | -------- |
| `claude` | `~/.claude` (mode 0700) with `agents/`, `commands/`, `skills/`, `rules/`, `output-styles/` and `hooks/`, the commit-signing guard, the no-session-links hook, the [ways of working](#ways-of-working) rule, skills and hook, and a `keybindings.json` (Enter adds a new line, Ctrl+Enter or Shift+Enter sends) and `settings.json` merged into whatever is already there. Honours `CLAUDE_CONFIG_DIR`. On Windows, PowerShell versions of the no-session-links and ways-of-working hooks, the commit-signing rule without its guard hook, and no `jq`. |
| `git`  | Global gitignore (`core.excludesfile`). Linux and Windows. |
| `pwsh` | Windows only: the PowerShell 7 profile (`Documents\PowerShell\profile.ps1`) and its numbered `profile.d\` drop-ins: a port of the zsh prompt, PSReadLine keys, in-memory history and suggestions, completion for uv and op, the direnv hook, `alert` and the `ws` workspace picker. Loaded in interactive sessions only. |
| `podman` | A persistent registry credentials file, `~/.config/containers/auth.json` (mode 0600), and `~/.docker/config.json` as a link to it. |
| `zsh`  | `~/.zshenv`, `~/.zshrc` and the numbered `~/.zshrc.d/` drop-ins: prompt, completions, keybindings, aliases and the `ws` workspace picker. |

### Dependencies

A module is skipped outright unless the command matching its name exists, so
that check is the only hard gate. Beyond it, dependencies fall into two tiers —
**neither prevents the configuration from being installed**:

- **Soft** — the configuration works without them but loses real functionality.
  Reported as errors and the module reports failure, so the run exits non-zero
  and you notice. The install still completes, and the features start working on
  the next shell once the dependency is present — no reinstall needed.
- **Optional** — nice to have. Reported as warnings only, and not at all when
  installing for root, which rarely has per-user tools like `uv` or `nvm`.

| Module | Requires | Soft | Optional |
| ------ | -------- | ---- | -------- |
| `claude` | `claude` | `jq`, `python3` | `cz` (commitizen) |
| `git`  | `git` | — | — |
| `podman` | `podman` | — | — |
| `zsh`  | `zsh` | `fzf`, `git`, `zsh-common`, `zsh-autosuggestions`, `zsh-syntax-highlighting` | `op`, `uv`, `pulumi`, `direnv`, `nvm`, `ant`, `podman`, `xdg-open`, `gh` |

On Windows:

| Module | Requires | Soft | Optional |
| ------ | -------- | ---- | -------- |
| `claude` | `claude` | — | `cz` (commitizen) |
| `git`  | `git` | — | — |
| `pwsh` | `pwsh` | `fzf` | `git`, `code`, `uv`, `op`, `direnv` |

The Windows `claude` module needs neither `jq` nor `python3`: it merges the
JSON in PowerShell, and its hooks are PowerShell scripts that Claude Code
runs with `pwsh`, or Windows PowerShell when `pwsh` is missing.

The `claude` module never overwrites `~/.claude/settings.json` or
`~/.claude/keybindings.json`, because Claude Code writes to the first
(`/model`, `/config`, `/permissions`, plugins) and you edit the second. Each
template is deep-merged in with `jq`: its values win, nested objects merge
key by key, lists are unioned, and every other key is kept. Keybinding
blocks merge by `context`, so the template's bindings go into your block for
the same context rather than a second one. Without `jq` a template is only
written where no file exists yet. On Windows, `install.ps1` does the same
merge in PowerShell, so it needs no `jq`.

### Ways of working

The `claude` module also installs a set of house defaults for contributing
and writing: a rule, `~/.claude/rules/wow-core.md`, and the `wow-*` skills
for commit messages, pull requests, branching, versioning, docs, Markdown,
diagrams and GitHub wikis. They apply only where you opt in. A `.wow` file
turns them on for the directory that holds it and everything below it,
inside `~/workspaces` (`$WORKSPACE_DIR`, which `~/.zshenv` sets):

```bash
touch ~/workspaces/.wow                        # every repository
touch ~/workspaces/github.com/.wow             # every GitHub repository
touch ~/workspaces/github.com/OWNER/REPO/.wow  # one repository
```

A hook, `~/.claude/hooks/wow_marker.sh`, tells Claude when a directory it
works in turns on or off, and denies the `wow-*` skills while nothing it has
touched is marked. Without a marker nothing changes: Claude ignores them and
follows each project's own guidance. A project's `CLAUDE.md` can override
any default. Unless you ask, Claude never mentions the rule, the skills or a
marker in what it writes for a project (files, commits, pull requests,
issues and comments), so other contributors don't need them. The global
gitignore ignores `.wow`, so a marker stays local. Delete it to turn them
off again.

### Commit-signing guard

When commits are signed through something that needs you in person, such as
1Password with Windows Hello, an agent working while you're away hits a
signing timeout and tends to retry with signing switched off. The `claude`
module installs a guard against that: a hook,
`~/.claude/hooks/commit_signing_guard.sh` (logic in the `.py` beside it), and
a rule, `~/.claude/rules/commit-signing.md`.

- It always denies signing bypasses: `--no-gpg-sign`, `tag --no-sign`,
  `-c`/`--config-env`/`GIT_CONFIG_*`/`HOME`/`sudo` overrides of the signing
  settings, aliases that do any of that, `git config` changes to them, edits
  of git config files, unsigned plumbing such as `commit-tree`, and changes
  to the guard itself. There is no opt-out; to commit unsigned, run the
  command yourself.
- When a git command fails to sign, or hangs until it times out, it tells
  the agent to stop and report, shows you a notice, and denies every signing
  git command in that session (subagents included) until your next message.

Commands are parsed like a shell (quotes, heredocs, `$(...)`, `sh -c`), so
commit messages that mention these flags are fine. It needs `python3` (the
standard library only) and does nothing without it. It is a guard rail
against an agent's habits, not a security boundary: a script on disk, another
interpreter or another git client can still get past it. Its tests are in
`src/modules/claude/tests/`.

On Windows only the rule is installed, with a last line saying nothing
enforces it: a PowerShell version of the hook took about a second per tool
call.

### No session links

Claude Code can add a link to its session (`claude.ai/code/session_...`) to
commit messages and pull requests, and in a public repository anyone can
follow it. The `claude` module turns that off with `attribution.sessionUrl:
false`, and installs a rule, `~/.claude/rules/no-session-links.md`, and a
hook, `~/.claude/hooks/no_session_links.sh` (logic in the `.py` beside it),
that denies any tool call that would publish one another way.

- It looks for session URLs, `Claude-Session:` trailers, session IDs and
  `claude.ai` artifact links.
- It checks Bash and Monitor commands, the message and body files they pass
  to `git` and `gh` (`-F`, `--file`, `--body-file`, `--notes-file`), text
  written with Edit, Write, MultiEdit and NotebookEdit, and every MCP tool's
  input.
- On `git push`, it checks the messages of commits no remote has yet.

The `Co-Authored-By:` footer and the "Generated with Claude Code" line are
fine. Like the guard, it needs `python3`, does nothing without it, and is a
guard rail rather than a security boundary.

The module also sets `attribution.pr` to `""`, so Claude Code adds no
"Generated with Claude Code" line to pull request descriptions. When GitHub
squash-merges a pull request, it credits Claude from the `Co-Authored-By:`
footer on the branch's commits.

`ant` is the [Claude Platform CLI](https://github.com/anthropics/anthropic-cli),
not the `ant` package from apt, which is Apache Ant. Its zsh completion is
generated on demand like the other optional tools.

With `podman` installed and its user API socket listening
(`systemctl --user enable --now podman.socket`), zsh points `DOCKER_HOST` at
that socket, so Docker clients such as VS Code Dev Containers use rootless
podman. Root uses the system socket instead
(`/run/podman/podman.sock`, from `sudo systemctl enable --now podman.socket`).
A `DOCKER_HOST` you set yourself wins. The WSL user-data makes podman-compose
the provider for `podman compose`, and for `docker compose` through
`podman-docker`.

`podman login` saves credentials in `$XDG_RUNTIME_DIR/containers/auth.json`
by default, which lasts for the session. The `podman` module creates
`~/.config/containers/auth.json`, which persists, and links
`~/.docker/config.json` to it, so Docker tooling such as VS Code Dev
Containers (pulling private features) sees the same persistent credentials.
With `podman` installed and that file present, zsh exports
`REGISTRY_AUTH_FILE` pointing at it, so `podman login`, `buildah` and
`skopeo` read and write the persistent file instead. A `REGISTRY_AUTH_FILE`
you set yourself wins. An existing `~/.docker/config.json` is never replaced,
and while it is a separate file zsh leaves `REGISTRY_AUTH_FILE` unset, since
setting it would stop podman reading that file's credentials: move its
`auths` (and any `credHelpers`) into podman's file, delete it, and rerun the
installer.

`zsh-common` is detected by probing zsh's own `$fpath` for `vcs_info`,
`compinit` and `add-zsh-hook` rather than by asking a package manager, so the
check works on any distribution.

> The Linux install scripts are POSIX `sh` so they run anywhere. Only the files
> they seed are zsh-specific. Their Windows twins are PowerShell, and run on
> PowerShell 7 and Windows PowerShell 5.1.

## WSL provisioning

[froazin/wsl](https://github.com/froazin/wsl) holds a cloud-init config
that builds an Ubuntu 26.04 WSL instance from scratch, with every package
these modules depend on, and installs these dotfiles into it for the user
and for root. Its README has the install steps.

## Design docs

How each part works, and why it's built that way, for anyone changing the
code:

- [Installer](docs/installer.md): `install.sh` and `install.ps1`, module
  discovery and the shared helpers.
- [git module](docs/git-module.md) and [podman module](docs/podman-module.md).
- [pwsh module](docs/pwsh-module.md), the PowerShell profile and `ws` on
  Windows.
- [zsh module](docs/zsh/overview.md).
- [claude module](docs/claude/overview.md), the
  [commit-signing guard](docs/claude/commit-signing-guard.md),
  [no session links](docs/claude/no-session-links.md) and the
  [ways of working](docs/claude/ways-of-working.md).
- [CI](docs/ci.md): the checks each pull request and release runs, and
  the code review on each pull request.
- [Releases](docs/releases.md): how `main` is released, with a version
  commitizen works out.

---
Happy coding! :rocket:
