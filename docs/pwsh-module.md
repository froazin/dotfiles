# pwsh module

How the `pwsh` module installs a PowerShell 7 profile on Windows, and how its drop-ins work: the prompt, line editing and history, generated tab completion, the direnv hook and the `ws` workspace picker. It's for engineers who change [`src/modules/pwsh/`](../src/modules/pwsh/).

## Contents

1. [Overview](#overview)
1. [How it installs](#how-it-installs)
1. [How it loads](#how-it-loads)
1. [Options and line editing](#options-and-line-editing)
1. [The prompt](#the-prompt)
1. [Completion registry](#completion-registry)
1. [direnv](#direnv)
1. [The workspace picker](#the-workspace-picker)
1. [Errors and logging](#errors-and-logging)
1. [Security and privacy](#security-and-privacy)
1. [Decisions](#decisions)
1. [Limits](#limits)
1. [Sources](#sources)

## Overview

The module is the Windows counterpart of the [zsh module](zsh/overview.md): a profile that only loads numbered drop-ins, and drop-ins that each hold one topic. They cover the environment, PSReadLine's keys, history and suggestions, a native port of the zsh prompt, generated completion for uv, uvx and the 1Password CLI, the direnv hook, `browse` and `alert`, the `ws` workspace picker and `pwshup`. Where zsh and PowerShell differ, the choices were made with the maintainer, item by item; [Decisions](#decisions) lists them.

- Only [`install.ps1`](../src/install.ps1) runs it: it has a [`bootstrap.ps1`](../src/modules/pwsh/bootstrap.ps1) and no `bootstrap.sh`. It runs when `pwsh` is on `PATH` (see [Installer](installer.md)), even when the installer itself runs in Windows PowerShell 5.1.
- It configures PowerShell 7 only. Windows PowerShell 5.1 keeps its own profile, which the module doesn't touch.
- It doesn't install packages. The drop-ins check for each tool when they're used.

```text
src/modules/pwsh/
├── bootstrap.ps1                  Invoke-Bootstrap
└── templates/
    ├── profile.ps1                installed as $PROFILE.CurrentUserAllHosts
    └── profile.d/
        ├── 00-options.ps1         environment, bell and history
        ├── 05-keybindings.ps1     PSReadLine keys
        ├── 10-completion.ps1      the completion registry and its cache
        ├── 20-tools.ps1           the direnv hook
        ├── 30-prompt.ps1          the prompt
        ├── 40-aliases.ps1         browse and alert
        ├── 50-functions.ps1       Enter-Workspace (ws, workspace, workspaces) and wsc
        ├── 60-maintenance.ps1     Update-ShellCompletion (pwshup)
        └── 90-predictions.ps1     inline suggestions
```

## How it installs

`Invoke-Bootstrap` runs three steps and returns `$false` if any failed. Every step runs, even when an earlier one failed.

1. **Soft dependencies** (`$PwshSoftDeps`): `fzf`, which the picker needs. A missing one logs an error and fails the module, but the profile is still installed.
1. **Optional dependencies** (`$PwshOptionalDeps`): `git`, for the picker's preview, `code`, for `ws -c`, `uv` and `op`, for their completion, and `direnv`. A missing one logs a warning, and its integration stays dormant until it's installed.
1. **Templates:** `Get-PwshProfilePath` runs `pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts'` and installs `profile.ps1` there with `Install-File`, then every `templates/profile.d/*.ps1` into `profile.d/` beside it. A new drop-in needs no change to `bootstrap.ps1`.

`$PROFILE.CurrentUserAllHosts` is `Documents\PowerShell\profile.ps1`, in whatever folder Windows calls Documents: with OneDrive's folder backup on, that's `OneDrive\Documents` (observed). PowerShell loads it in every PowerShell 7 host (the console, Windows Terminal and VS Code) before the host's own profile.

### Controlled folder access

Windows Security's Controlled folder access, part of ransomware protection, protects Documents from any program that isn't on its allow list, and PowerShell isn't on it. With it on, Windows Security shows "Protected folder access blocked" for `pwsh.exe` (or `powershell.exe`), and each file fails with `Failed to write <...>: Access to the path '...' is denied.` (observed).

Don't allow PowerShell through: that lets any script change your protected folders for good. Instead:

1. Turn Controlled folder access off: Windows Security > Virus & threat protection > Ransomware protection.
1. Run the installer again.
1. Turn it back on.

When the profile fails to install and `Get-MpPreference` says Controlled folder access is on (`EnableControlledFolderAccess` is 1, which needs no admin rights), `bootstrap.ps1` logs these steps as an error. It can't tell for certain that Controlled folder access was the cause, so the message says "probably". Nothing the profile does at runtime writes to Documents: the completion cache is in `%LOCALAPPDATA%`.

## How it loads

[`profile.ps1`](../src/modules/pwsh/templates/profile.ps1) only dot-sources `profile.d\*.ps1` beside it, in name order, so their functions and aliases land in the session's global scope.

- **Interactive sessions only**, as zsh reads `.zshrc`. PowerShell also loads profiles for `pwsh -Command` and `-File`, which scripts and, probably, Claude Code's PowerShell hooks use. So `profile.ps1` loads nothing when the command line has `-Command`, `-File` or `-EncodedCommand` (or a shorter spelling) without `-NoExit`, or has `-NonInteractive`. VS Code's terminal starts pwsh with `-NoExit -Command`, so it still loads (each case observed against sample command lines). A script path given without `-File`, as in `pwsh script.ps1`, isn't recognised, and loads the drop-ins.
- A drop-in that throws prints one warning naming it, and the rest still load.
- `-Filter '*.ps1'` also matches `*.ps1xml` on Windows, so the loop checks the extension again.
- The loop variable is removed afterwards, so the profile leaves nothing behind but what the drop-ins define.
- Personal settings go in a drop-in of your own, which a reinstall doesn't touch, or in the host profile (`Microsoft.PowerShell_profile.ps1`), which loads after this one.

| Drop-in | Holds |
| --- | --- |
| [00-options.ps1](../src/modules/pwsh/templates/profile.d/00-options.ps1) | `WORKSPACE_DIR`, `EDITOR` and `VISUAL`, `VIRTUAL_ENV_DISABLE_PROMPT`, the bell and history |
| [05-keybindings.ps1](../src/modules/pwsh/templates/profile.d/05-keybindings.ps1) | Windows edit mode, menu completion on Tab, <kbd>Ctrl</kbd>+<kbd>X</kbd> <kbd>Ctrl</kbd>+<kbd>E</kbd> and <kbd>Alt</kbd>+<kbd>H</kbd> |
| [10-completion.ps1](../src/modules/pwsh/templates/profile.d/10-completion.ps1) | The [completion registry](#completion-registry), its cache and the lazy loader |
| [20-tools.ps1](../src/modules/pwsh/templates/profile.d/20-tools.ps1) | The [direnv](#direnv) hook |
| [30-prompt.ps1](../src/modules/pwsh/templates/profile.d/30-prompt.ps1) | [The prompt](#the-prompt) |
| [40-aliases.ps1](../src/modules/pwsh/templates/profile.d/40-aliases.ps1) | `browse`, which opens a file, folder or URL with its default app, and `alert` |
| [50-functions.ps1](../src/modules/pwsh/templates/profile.d/50-functions.ps1) | `Enter-Workspace`, its aliases `ws`, `workspace` and `workspaces`, `wsc`, and tab completion for them |
| [60-maintenance.ps1](../src/modules/pwsh/templates/profile.d/60-maintenance.ps1) | `Update-ShellCompletion`, aliased as `pwshup` |
| [90-predictions.ps1](../src/modules/pwsh/templates/profile.d/90-predictions.ps1) | Inline suggestions, like zsh-autosuggestions |

Every integration checks for its tool with `Get-Command -CommandType Application` and does nothing, silently, when it's missing. Anything that sets PSReadLine options checks first that PSReadLine is loaded.

On a warm start with uv, op and direnv installed, the drop-ins took about 400 ms between them, on top of the 130 ms PSReadLine takes to load in any interactive session (observed). Most of it is `Get-Command` searching a long `PATH`, and child processes: `20-tools.ps1` about 125 ms (direnv's hook and its first export), `10-completion.ps1` about 115 ms, and `00-options.ps1` about 90 ms while `EDITOR` is unset. Every other drop-in took 20 ms or less, the prompt's 16 ms included.

## Options and line editing

The twins of `.zshenv`, `00-options.zsh`, `05-keybindings.zsh` and zsh-autosuggestions, as the maintainer chose them:

- **`WORKSPACE_DIR`** is exported as `~\workspaces` unless it's already set, so everything started from the shell, Claude Code's hooks included, agrees with `ws`.
- **`EDITOR` and `VISUAL`:** only when `EDITOR` isn't set, `code --wait` when VS Code is installed and the session isn't elevated (or `REMOTE_CONTAINERS` is `true`), then `vim`, then `notepad`. zsh overwrites `EDITOR` every time; this doesn't.
- **`VIRTUAL_ENV_DISABLE_PROMPT=1`**, because the prompt shows the virtualenv itself.
- **History** stays in memory only: `HistorySaveStyle SaveNothing`, 50,000 lines, no duplicates, and a line that starts with a space is never recorded, as with zsh's `hist_ignore_space`. PSReadLine's history file isn't written.
- **Bell:** `BellStyle None`.
- **Keys:** PSReadLine's Windows edit mode, which already moves and deletes by word with <kbd>Ctrl</kbd>, plus zsh's menu completion on <kbd>Tab</kbd> (`MenuComplete`), <kbd>Ctrl</kbd>+<kbd>X</kbd> <kbd>Ctrl</kbd>+<kbd>E</kbd> to edit the line in `$VISUAL` or `$EDITOR` (`ViEditVisually`), and <kbd>Alt</kbd>+<kbd>H</kbd> for help on the command under the cursor (`ShowCommandHelp`, which replaces PSReadLine's default `ShowParameterHelp` there). Emacs keys, such as <kbd>Ctrl</kbd>+<kbd>A</kbd> to go to the start of the line, aren't bound.
- **Suggestions:** `PredictionSource HistoryAndPlugin` with `InlineView`, in the prompt's dim grey. <kbd>Right</kbd> or <kbd>End</kbd> accepts one. With history in memory, suggestions start empty in each new shell. PowerShell before 7.2 falls back to history alone, and a console that can't show them, such as one with redirected output, gets none, silently.

## The prompt

[`30-prompt.ps1`](../src/modules/pwsh/templates/profile.d/30-prompt.ps1) is a plain `prompt` function that ports zsh's, the devcontainers `common-utils` theme, without oh-my-posh:

```text
(venv) <logo> user[@host] -> dir (branch) $
```

| Segment | Does |
| --- | --- |
| `(venv)` | The virtualenv's directory name, or its parent's for `.venv` and `venv`, as in zsh |
| Logo | Nerd Font `nf-md-powershell` (U+F0A0A) in PowerShell blue, `#2671BE`; grey when elevated |
| `user[@host]` | `[Environment]::UserName`, then `@` and the machine name when `SSH_CONNECTION`, `SSH_CLIENT` or `SSH_TTY` is set |
| Arrow | U+279C, red when the last command failed. `$?` is read first, and pwsh sets it false for a non-zero native exit too |
| `dir` | The current directory's name, `~` at home, the drive root as it is, or the provider path elsewhere, such as `HKCU:\Software` |
| `(branch)` | See below |
| `$` | `#` when elevated |

The colours are zsh's hex colours as 24-bit escape codes. The git segment reads files rather than running git:

- `Get-PromptGitDir` walks up from the current directory to the nearest `.git`, following the `gitdir:` line in a linked worktree's or a submodule's `.git` file.
- `Get-PromptGitStatus` reads `HEAD`: the branch name, or the first seven characters of the commit when it's detached.
- It adds the operation in progress, as vcs_info's `actionformats` does: `rebase-i` or `rebase-m` (with the name of the branch being rebased, from `head-name`), `rebase`, `am` or `am/rebase`, `merge`, `cherry` or `bisect`.
- It skips network paths (`\\server\share`, `\\wsl$\...`), where the reads can stall, as zsh skips `/mnt`.

Each of these cases was observed in a scratch repository, and one prompt took about 4.4 ms inside a repository (observed), or about 26 ms with direnv installed, which the prompt runs first (see [direnv](#direnv)). Unlike zsh's, the prompt doesn't set the window title, and has no dirty marker and no per-repository opt-ins. See [Decisions](#decisions).

## Completion registry

The twin of zsh's [completion registry](zsh/overview.md#completion-registry). `$PwshOptionalCompletions` in `10-completion.ps1` lists each tool, the arguments that print its PowerShell completion, whether to load it lazily, and an optional patch:

| Tool | Generator | Loaded |
| --- | --- | --- |
| `uv` | `uv generate-shell-completion powershell` | On the first Tab |
| `uvx` | `uvx --generate-shell-completion powershell` | On the first Tab |
| `op` | `op completion powershell` | At startup, then patched |

`Update-PwshCompletionCache` writes `<name>.ps1` into `%LOCALAPPDATA%\powershell\completions` (`$XDG_DATA_HOME` or `~/.local/share` elsewhere), and returns the same statuses as zsh's `zcache_completion`: 0 regenerated, 1 already current, 2 not installed, 3 failed.

- It regenerates only when the file is missing, or the tool's binary is newer than it. A WinGet link, such as `op.exe` under `WinGet\Links`, is followed to the binary it points at.
- A failure leaves a marker in `.failed\<name>`. Startup doesn't retry until the binary changes, and `pwshup` forces a retry.
- The generator runs with `Start-Process` in the cache directory, so a tool that reads its working directory never acts on the project the shell opened in. Its output goes straight to the file, byte for byte, without passing through the console's encoding.
- **Lazy loading:** uv's script is about 760 KB and takes about 200 ms to load, and uvx's is in the same form (observed). Each only registers a native completer, so `Register-PwshLazyCompletion` registers a stand-in that loads the real script on the first Tab and asks PowerShell to complete the same input again. A script that defines functions its completer calls later, as op's does, has to load at startup in the profile's scope, or those functions disappear.
- **Patches:** op's generated script redirects `Invoke-Expression` rather than the `op` call inside it, so op printed `Completion ended with directive: ...` on every Tab (observed). Its patch moves the redirection into the command string.
- `pwshup` regenerates every entry and reports each, then tells you to open a new shell.

## direnv

`20-tools.ps1` loads `direnv hook pwsh` when direnv is installed and PowerShell is 7.2 or later, the oldest version direnv's hook accepts. That hook runs `direnv export pwsh` from `LocationChangedAction`, on every change of location only. zsh's runs before every prompt, so a new, edited or newly allowed `.envrc` in the current directory takes effect at the next prompt, where the pwsh hook alone would wait for a `cd`. Then:

- **Every prompt, as in zsh:** the drop-in defines `Update-DirenvEnvironment`, which runs `direnv export pwsh` and applies what it prints, and the prompt calls it before anything else. That also loads the directory the shell starts in. direnv prints nothing when nothing has changed, but starting it takes about 30 ms, so a prompt with direnv installed took about 26 ms rather than 4 ms (observed). The location hook stays too, so direnv still follows `cd` if another prompt, such as oh-my-posh, replaces this one.

- **`HOME`:** direnv finds its config, cache and data directories from `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and `XDG_DATA_HOME`, or else from `HOME`, and Windows sets none of them. Without one, every change of location printed `direnv: error couldn't find a configuration directory for direnv`, and setting only `XDG_CONFIG_HOME` moved the error on to the cache directory (both observed). So the drop-in sets `HOME` to the profile folder, `$HOME`, when it's unset: the value Git Bash and Git for Windows already use. Every program started from the shell sees it.
- **`DIRENV_BASH`:** direnv runs `.envrc` with bash, and the `bash.exe` it finds on a Windows `PATH` is usually WSL's launcher in `WindowsApps` (observed). Unless `DIRENV_BASH` is already set, the drop-in points it at Git for Windows' `bin\bash.exe`, found above each `git.exe` on `PATH`.
- **`DIRENV_WARN_TIMEOUT`** is `60s`, as in zsh.
- **Once per session:** a flag stops a second load of the profile chaining a second hook (observed: one hook after two loads). The variables the hook's script leaves behind are removed.

Observed with direnv 2.38.2 in a scratch directory, with `HOME` unset beforehand as in a normal Windows session: an `.envrc` created and allowed in the current directory loaded at the next prompt, an edit to it applied at the prompt after it was allowed, leaving the directory unloaded it and coming back loaded it again, all without errors.

## The workspace picker

The twin of zsh's `workspaces`. A workspace is a git repository at `<provider>/<org>/<repo>` under `$env:WORKSPACE_DIR`, or `~\workspaces` when that's unset.

| Command | Does |
| --- | --- |
| `ws` | Picks a workspace with fzf and goes there |
| `ws <query>` | Starts fzf with the query, and goes straight there if exactly one workspace matches |
| `ws -c` / `wsc` | Also opens it in VS Code: the `*.code-workspace` at its root (preferring `<repo>.code-workspace`), or the directory |
| `ws -h` | Prints the usage. `Get-Help ws` shows the comment-based help |

- **Listing:** `__ws_list` walks three levels of directories, hidden ones included, skipping `$RECYCLE.BIN`, and prints `<provider>/<org>/<repo>`, a tab and the full path for each, sorted.
- **Picking:** fzf shows only the first field (`--with-nth=1`) and returns the whole line, so the full path never has to be rebuilt from the name.
- **Preview:** fzf runs it in `pwsh -NoProfile` (`--with-shell`), and quotes the full path (`{2}`) for it. It shows the path, then `git status -sb` and the last ten commits when `git` is installed. It switches its own output to UTF-8 first, because pwsh otherwise writes redirected output in the console's code page and fzf reads UTF-8 (observed).
- **Encoding:** fzf reads and writes UTF-8, so `Enter-Workspace` sets `$OutputEncoding` and the console's output encoding to UTF-8 while fzf runs, then puts them back.
- **zsh spellings:** `--code`, `--help` and `--` work too, as well as PowerShell's `-Code`/`-c` and `-Help`/`-h`.
- **Errors:** a missing workspace directory, a missing fzf, a cancelled pick or a failed `Set-Location` writes a PowerShell error and changes nothing.
- **Administrator:** like zsh's rule for root, `ws -c` doesn't open VS Code from an elevated session, unless `REMOTE_CONTAINERS` is `true`.
- **Completion:** `Register-ArgumentCompleter` completes the query from the workspace names, matching anywhere in the name.

## Errors and logging

`bootstrap.ps1` logs with `Write-DotfilesLog` from [`install.ps1`](../src/install.ps1). A missing soft dependency is an error and an optional one a warning, and the messages say the profile is installed anyway. A profile path that `pwsh` doesn't report, or that isn't absolute, is an error and installs nothing.

## Security and privacy

- The templates hold no identifying data, and the module never reads any.
- The profile runs in every PowerShell 7 session, so treat a change to it as code every shell runs.
- The preview runs `git` in each workspace it shows, and git can run programs a repository's config names. Git for Windows' `safe.directory` check refuses a repository another user owns (git's documented behaviour), which covers what zsh's root check covers.
- With OneDrive's folder backup on, the profile and drop-ins sync to OneDrive with the rest of Documents.

## Decisions

- **`CurrentUserAllHosts`, not the host profile.** Every PowerShell 7 host loads it, and the user's own `Microsoft.PowerShell_profile.ps1` is left alone.
- **Ask pwsh for the path.** `$PROFILE` in `install.ps1` is Windows PowerShell's when it runs there, and the Documents folder can move. pwsh itself knows where it looks. It also follows `USERPROFILE` for a scratch install, where Documents is stored as `%USERPROFILE%\...` (observed).
- **Drop-ins, like zsh.** One topic per file keeps a change small, and a new drop-in installs without code changes.
- **`Enter-Workspace` with aliases.** An approved verb keeps PSScriptAnalyzer and `Get-Verb` happy, and the aliases keep the zsh names.
- **The full path in the line.** zsh exports `WS_DIR` for its preview to rebuild the path. Carrying it in a hidden field avoids quoting a joined path for another shell.
- **Export `WORKSPACE_DIR`.** The Windows hooks and `ws` work out the same default themselves, but one exported value means a different default can't creep in anywhere.
- **A native prompt, not oh-my-posh.** Every segment of the zsh theme ports to a `prompt` function, and reading `.git` directly costs a few milliseconds without a process, so oh-my-posh would add a dependency and nothing the theme needs.
- **Choices made with the maintainer:** the PowerShell glyph rather than the Ubuntu logo; no dirty marker, because `git status` on Windows is too slow for every prompt; no per-repository opt-ins for now; the window title left to the terminal; Windows edit mode with zsh's extras rather than emacs keys; history in memory, as in zsh; menu completion; inline suggestions; `alert` as in zsh, with no Windows notification; direnv checked before every prompt, as in zsh, for about 30 ms a prompt.
- **Not ported, by choice:** fzf's key bindings, nvm (or any Node.js manager), the `ll`, `la` and `l` aliases, a `zshreload` twin and changes to `PATH`. Linux-only settings (`BROWSER`, `LIBVIRT_DEFAULT_URI`, `GCC_COLORS`, the podman variables and `dircolors`) have nothing to port to: `$PSStyle.FileInfo` already colours `Get-ChildItem`.
- **Interactive only.** The drop-ins configure a terminal, so a script or hook run with `pwsh -Command` gets none of them, and none of their cost.

## Limits

- Windows only for now: nothing installs the profile with pwsh on Linux.
- A `profile.ps1` already in place is overwritten, with a warning. There's no backup and no merge, as with zsh's `.zshrc`.
- A drop-in removed from the repository stays installed until it's deleted by hand.
- The preview needs an fzf with `--with-shell`. With fzf 0.75.0, `ws <query>` went straight to the one match, a path holding `'` and `é` included, and a query with no match failed cleanly (observed). The preview command was run by hand, with `{2}` quoted as fzf quotes it for PowerShell, not from fzf's interactive UI (inferred from fzf's source).
- Each preview starts `pwsh`, which takes a few hundred milliseconds.
- zsh patches uv's completion so `uv run` completes the project's commands. The PowerShell version has no such patch, so `uv run` completes only what uv's own script offers.
- `op`'s patch matches one line of the script `op` generates today. If a future `op` changes that line, the patch does nothing and the message comes back.
- direnv needs Git for Windows for its bash, or `DIRENV_BASH` naming another one. With neither, it falls back to the `bash` on `PATH`, usually WSL's, and `.envrc` files won't load (inferred, untested).
- `DIRENV_WARN_TIMEOUT` is set whenever direnv loads, replacing a value you set yourself, as zsh does.
- The prompt's logo needs a Nerd Font, as zsh's does. Without one it shows as a box.
- `alert` shows `$LASTEXITCODE` beside `failed`, which may be left over from an earlier native command when the failing command was a cmdlet.
- `ViEditVisually` with `EDITOR` set to `code --wait` wasn't tried from an interactive console (untested).
- No interactive session was run: the drop-ins were tested by dot-sourcing them into a non-interactive pwsh with PSReadLine imported.

## Sources

- https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles
- https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter
- https://github.com/junegunn/fzf
- https://direnv.net/docs/hook.html
- https://learn.microsoft.com/powershell/module/psreadline/set-psreadlineoption
- https://learn.microsoft.com/powershell/module/psreadline/about/about_psreadline_functions
- https://github.com/devcontainers/features/tree/main/src/common-utils
- https://docs.astral.sh/uv/getting-started/installation/#shell-autocompletion
- https://developer.1password.com/docs/cli/reference/commands/completion
