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
| `claude` | `~/.claude` (mode 0700) with `agents/`, `commands/`, `skills/`, `rules/`, `output-styles/` and `hooks/`, and a `settings.json` merged into whatever Claude Code has already written there. Honours `CLAUDE_CONFIG_DIR`. |
| `git`  | Global gitignore (`core.excludesfile`). |
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
| `claude` | `claude` | `jq` | — |
| `git`  | `git` | — | — |
| `zsh`  | `zsh` | `fzf`, `git`, `zsh-common`, `zsh-autosuggestions`, `zsh-syntax-highlighting` | `op`, `uv`, `pulumi`, `direnv`, `nvm`, `ant` |

The `claude` module never overwrites `~/.claude/settings.json`, because Claude
Code writes to it too (`/model`, `/config`, `/permissions`, plugins). The
template is deep-merged in with `jq`: its values win, nested objects merge
key by key, lists are unioned, and every other key is kept. Without `jq` the
template is only written where no settings exist yet.

`ant` is the [Claude Platform CLI](https://github.com/anthropics/anthropic-cli),
not the `ant` package from apt, which is Apache Ant. Its zsh completion is
generated on demand like the other optional tools.

`zsh-common` is detected by probing zsh's own `$fpath` for `vcs_info`,
`compinit` and `add-zsh-hook` rather than by asking a package manager, so the
check works on any distribution.

> The install scripts are POSIX `sh` so they run anywhere. Only the files they
> seed are zsh-specific.

## WSL provisioning

`src/wsl/ubuntu.user-data` is a cloud-init config that builds an Ubuntu 26.04 WSL
instance from scratch:

- installs every package the modules above depend on, plus containers and a
  KVM/libvirt stack for running VMs inside WSL;
- writes `/etc/wsl.conf` and disables swap to match `src/wsl/.wslconfig`;
- bridges Windows tools (VS Code, 1Password CLI, OpenSSH) into the Linux
  `PATH`, and sets `$BROWSER` so `xdg-open` opens things in Windows;
- creates the user with zsh and passwordless sudo, when a username is given;
- installs `uv`, `pulumi`, `nvm`, Claude Code (`claude`) and the Claude
  Platform CLI (`ant`) as that user, and the Claude Code VS Code extension
  into the instance's VS Code server (this needs VS Code and its WSL extension
  on Windows);
- configures git, then clones this repo and runs `install.sh`;
- makes zsh root's login shell and runs `install.sh` for root too, so
  `sudo su` keeps the same shell and prompt. Without a username, root's copy
  comes from a temporary clone.

The user-data holds nothing personal. Your username and git identity go in the
meta-data, which cloud-init reads alongside it and which stays on your machine:

| Repo file | Copy to |
| --------- | ------- |
| `src/wsl/.wslconfig` | `%USERPROFILE%\.wslconfig` |
| `src/wsl/ubuntu.user-data` | `%USERPROFILE%\.cloud-init\ubuntu.user-data` |
| `src/wsl/ubuntu.meta-data` (fill it in) | `%USERPROFILE%\.cloud-init\ubuntu.meta-data` |

cloud-init matches both files by instance name, so install the distro as
`Ubuntu` from PowerShell:

```powershell
wsl --install Ubuntu-26.04 --name Ubuntu
```

cloud-init runs on first boot only, and the first launch waits for it. When it
finishes, restart the instance so the `wsl.conf` settings and the new group
memberships take effect:

```powershell
wsl --terminate Ubuntu
```

If the meta-data gives no `username`, WSL asks you to create a user as normal,
and that user gets zsh and the virtualisation groups. Root is already
configured. Finish setting up the user yourself:

```bash
curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
curl -fsSL https://get.pulumi.com | sh -s -- --no-edit-path
git clone https://github.com/nvm-sh/nvm.git ~/.nvm
git -C ~/.nvm checkout "$(git -C ~/.nvm describe --abbrev=0 --tags --match 'v[0-9]*' "$(git -C ~/.nvm rev-list --tags --max-count=1)")"
curl -fsSL https://claude.ai/install.sh | bash
v="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/anthropics/anthropic-cli/releases/latest)"; v="${v##*/v}"
case "$(uname -m)" in aarch64) a=arm64 ;; *) a=amd64 ;; esac
mkdir -p ~/.local/bin && curl -fsSL "https://github.com/anthropics/anthropic-cli/releases/download/v$v/ant_${v}_linux_$a.tar.gz" | tar -xzmf - -C ~/.local/bin ant
code --install-extension Anthropic.claude-code
git clone https://github.com/froazin/dotfiles.git ~/workspaces/github.com/froazin/dotfiles
# Until the dotfiles' ~/.zshenv exists, the installer cannot see tools in ~/.local/bin.
PATH="$HOME/.local/bin:$HOME/.pulumi/bin:$PATH" sh ~/workspaces/github.com/froazin/dotfiles/src/install.sh
```

To test changes, copy the files as `ci-test.user-data` and `ci-test.meta-data`
to match a throwaway instance:

```powershell
wsl --install Ubuntu-26.04 --name ci-test
wsl --unregister ci-test
```

---
Happy coding! :rocket:
