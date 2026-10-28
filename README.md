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
defines a `bootstrap()` function. A module is skipped entirely unless a command
matching its directory name is on `PATH`.

| Module | Installs |
| ------ | -------- |
| `claude` | `~/.claude` (mode 0700) with `agents/`, `commands/`, `skills/`, `rules/`, `output-styles/` and `hooks/`, the commit-signing guard, the no-session-links hook, and a `keybindings.json` (Enter adds a new line, Ctrl+Enter or Shift+Enter sends) and `settings.json` merged into whatever is already there. Honours `CLAUDE_CONFIG_DIR`. |
| `git`  | Global gitignore (`core.excludesfile`). |
| `podman` | A persistent registry credentials file, `~/.config/containers/auth.json` (mode 0600), and `~/.docker/config.json` as a link to it. |
| `zsh`  | `~/.zshenv`, `~/.zshrc` and the numbered `~/.zshrc.d/` drop-ins: prompt, completions, keybindings, aliases, the `ws` workspace picker and the first-login setup of a [ways-of-working repository](#ways-of-working). |

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
| `claude` | `claude` | `jq`, `python3` | — |
| `git`  | `git` | — | — |
| `podman` | `podman` | — | — |
| `zsh`  | `zsh` | `fzf`, `git`, `zsh-common`, `zsh-autosuggestions`, `zsh-syntax-highlighting` | `op`, `uv`, `pulumi`, `direnv`, `nvm`, `ant`, `podman`, `xdg-open`, `gh` |

The `claude` module never overwrites `~/.claude/settings.json` or
`~/.claude/keybindings.json`, because Claude Code writes to the first
(`/model`, `/config`, `/permissions`, plugins) and you edit the second. Each
template is deep-merged in with `jq`: its values win, nested objects merge
key by key, lists are unioned, and every other key is kept. Keybinding
blocks merge by `context`, so the template's bindings go into your block for
the same context rather than a second one. Without `jq` a template is only
written where no file exists yet.

### Ways of working

A ways-of-working repository holds your shared working practices for Claude
Code, with a `user-config/` directory that belongs in `~/.claude`. Put its
clone URL in `~/.config/ways-of-working/repo` (the WSL user-data writes it
from the meta-data's `ways_of_working`):

```bash
mkdir -p ~/.config/ways-of-working
echo https://github.com/OWNER/ways-of-working.git > ~/.config/ways-of-working/repo
```

Until it's cloned, every zsh with a terminal runs `wow-setup` before its first
prompt:

1. It clones the repository to `~/workspaces/<host>/<owner>/<repo>`, where
   `ws` finds it.
1. If the clone fails and it's an `https` GitHub repository, it runs
   `gh auth login --web` when gh isn't logged in yet, then clones it with
   `gh repo clone`. That's how a private repository gets cloned on a new
   machine.
1. It copies `user-config/` into `~/.claude` (`CLAUDE_CONFIG_DIR` if set).

Once the clone exists, new shells skip it. Run `wow-setup` again after a
`git pull` to copy the changes, and delete the config file to stop a failed
setup from asking again. It never runs as root, or in a shell without a
terminal, such as the one VS Code starts to read your environment.

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
"Generated with Claude Code" line to pull request descriptions. Pull
requests credit Claude with the same `Co-Authored-By:` footer as commits.

`ant` is the [Claude Platform CLI](https://github.com/anthropics/anthropic-cli),
not the `ant` package from apt, which is Apache Ant. Its zsh completion is
generated on demand like the other optional tools.

With `podman` installed and its user API socket listening
(`systemctl --user enable --now podman.socket`), zsh points `DOCKER_HOST` at
that socket, so Docker clients such as `docker compose` or VS Code Dev
Containers use rootless podman. Root uses the system socket instead
(`/run/podman/podman.sock`, from `sudo systemctl enable --now podman.socket`).
A `DOCKER_HOST` you set yourself wins.

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

> The install scripts are POSIX `sh` so they run anywhere. Only the files they
> seed are zsh-specific.

## WSL provisioning

`src/wsl/Ubuntu-26.04.user-data` is a cloud-init config that builds an Ubuntu
26.04 WSL instance from scratch:

- installs every package the modules above depend on, plus containers and a
  KVM/libvirt stack for running VMs inside WSL;
- enables podman's Docker-compatible API socket (`podman.socket`): rootless
  for every user, and the system socket for root;
- writes `/etc/wsl.conf` and disables swap to match `src/wsl/.wslconfig`;
- bridges Windows tools (VS Code, 1Password CLI, OpenSSH, `clip`) into the
  Linux `PATH`, and sets `$BROWSER` so `xdg-open` opens things in Windows;
- creates the user with zsh and passwordless sudo, when a username is given;
- installs `uv`, `pulumi`, `nvm`, Claude Code (`claude`) and the Claude
  Platform CLI (`ant`) as that user, and the VS Code extensions listed in the
  meta-data's `vscode_extensions` (Claude Code and Python to start with) into
  the instance's VS Code server (this needs VS Code and its WSL extension on
  Windows);
- installs the GitHub CLI extensions listed in the meta-data's
  `gh_extensions` (`gh act`, to run GitHub Actions workflows locally, to start
  with) as that user. Public extensions install before you log in to gh;
- configures git, then clones this repo and runs `install.sh`. With a
  `git_signingkey`, commits are signed, and a literal key (not a key file
  path) goes in `~/.config/git/allowed_signers`, so
  `git log --show-signature` can verify them;
- with a `ways_of_working` clone URL, writes it to
  `~/.config/ways-of-working/repo`, so your first login sets up the
  [ways-of-working repository](#ways-of-working);
- makes zsh root's login shell and runs `install.sh` for root too, so
  `sudo su` keeps the same shell and prompt. Without a username, root's copy
  comes from a temporary clone.

The user-data holds nothing personal. Your username, git identity, VS Code
extensions and gh extensions go in the meta-data, which cloud-init reads
alongside it and which stays on your machine:

| Repo file | Copy to |
| --------- | ------- |
| `src/wsl/.wslconfig` | `%USERPROFILE%\.wslconfig` |
| `src/wsl/Ubuntu-26.04.user-data` | `%USERPROFILE%\.cloud-init\Ubuntu-26.04.user-data` |
| `src/wsl/Ubuntu-26.04.meta-data` (fill it in) | `%USERPROFILE%\.cloud-init\Ubuntu-26.04.meta-data` |

cloud-init matches both files by instance name, so install the distro under
its default name, `Ubuntu-26.04`, from PowerShell:

```powershell
wsl --install Ubuntu-26.04
```

cloud-init runs on first boot only, and the first launch waits for it. When it
finishes, restart the instance so the `wsl.conf` settings and the new group
memberships take effect:

```powershell
wsl --terminate Ubuntu-26.04
```

If the meta-data gives no `username`, WSL asks you to create a user as normal,
and that user gets zsh and the virtualisation groups. Root is already
configured. Finish setting up the user yourself:

```bash
curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
curl -fsSL https://get.pulumi.com | sh -s -- --no-edit-path
git clone https://github.com/nvm-sh/nvm.git ~/workspaces/github.com/nvm-sh/nvm
cd ~/workspaces/github.com/nvm-sh/nvm
git checkout "$(git describe --abbrev=0 --tags --match 'v[0-9]*' "$(git rev-list --tags --max-count=1)")"
# Installs that release into ~/.nvm. The zsh config from these dotfiles loads it, so leave the profiles alone.
PROFILE=/dev/null bash install.sh
cd
curl -fsSL https://claude.ai/install.sh | bash
v="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/anthropics/anthropic-cli/releases/latest)"; v="${v##*/v}"
case "$(uname -m)" in aarch64) a=arm64 ;; *) a=amd64 ;; esac
mkdir -p ~/.local/bin && curl -fsSL "https://github.com/anthropics/anthropic-cli/releases/download/v$v/ant_${v}_linux_$a.tar.gz" | tar -xzmf - -C ~/.local/bin ant
# The extensions in your meta-data's vscode_extensions, e.g.:
code --install-extension Anthropic.claude-code --install-extension ms-python.python
# The extensions in your meta-data's gh_extensions, for example:
gh extension install https://github.com/nektos/gh-act
git clone https://github.com/froazin/dotfiles.git ~/workspaces/github.com/froazin/dotfiles
# Until the ~/.zshenv from these dotfiles exists, the installer cannot see tools in ~/.local/bin.
PATH="$HOME/.local/bin:$HOME/.pulumi/bin:$PATH" sh ~/workspaces/github.com/froazin/dotfiles/src/install.sh
# With a ways-of-working repository, your next shell sets it up.
mkdir -p ~/.config/ways-of-working
echo https://github.com/OWNER/ways-of-working.git > ~/.config/ways-of-working/repo
```

To test changes, copy the files as `ci-test.user-data` and `ci-test.meta-data`
to match a throwaway instance:

```powershell
wsl --install Ubuntu-26.04 --name ci-test
wsl --unregister ci-test
```

---
Happy coding! :rocket:
