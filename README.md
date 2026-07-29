# Dotfiles

Feel free to use and adapt these configurations for your own setup.

## Usage

```bash
# 1. Clone the repository
git clone https://github.com/froazin/dotfiles.git
cd dotfiles

# 2. Run the install script
chmod +x ./src/install.sh 
& ./src/install.sh
```

## Modules

Each directory under `src/modules/` is a module with a `bootstrap.sh` that
defines a `bootstrap()` function. A module is skipped entirely unless a command
matching its directory name is on `PATH`.

| Module | Installs |
| ------ | -------- |
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
- **Optional** — nice to have. Reported as warnings only.

| Module | Requires | Soft | Optional |
| ------ | -------- | ---- | -------- |
| `git`  | `git` | — | — |
| `zsh`  | `zsh` | `fzf`, `git`, `zsh-common`, `zsh-autosuggestions`, `zsh-syntax-highlighting` | `op`, `uv`, `pulumi`, `direnv` |

`zsh-common` is detected by probing zsh's own `$fpath` for `vcs_info`,
`compinit` and `add-zsh-hook` rather than by asking a package manager, so the
check works on any distribution.

> The install scripts are POSIX `sh` so they run anywhere. Only the files they
> seed are zsh-specific.

---
Happy coding! :rocket:
