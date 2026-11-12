# Shell integrations for optional tools. Each one does nothing when its tool
# isn't installed.

# direnv: its pwsh hook needs PowerShell 7.2, and runs on every change of
# location. Once per session, so reloading the profile doesn't chain a second
# hook: profile.ps1 dot-sources this file, so the flag is a session global.
if (-not $__dotfiles_direnv -and
    ($PSVersionTable.PSVersion.Major -gt 7 -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -ge 2)) -and
    (Get-Command direnv -CommandType Application -ErrorAction SilentlyContinue)) {

    # direnv finds its config, cache and data directories from the XDG
    # variables or HOME, and Windows sets none of them: without this, every
    # change of location prints "couldn't find a configuration directory".
    # The profile folder, as Git Bash and Git for Windows use.
    if (-not $env:HOME) {
        $env:HOME = $HOME
    }

    # direnv runs .envrc with bash. The bash.exe on a Windows PATH is usually
    # WSL's launcher, so use Git for Windows' bash unless DIRENV_BASH is set.
    if (-not $env:DIRENV_BASH -and $env:OS -eq 'Windows_NT') {
        foreach ($__dotfiles_git in @(Get-Command git -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $__dotfiles_dir = Split-Path -Parent $__dotfiles_git.Source
            for ($__dotfiles_i = 0; $__dotfiles_i -lt 3 -and $__dotfiles_dir -and -not $env:DIRENV_BASH; $__dotfiles_i++) {
                if (Test-Path -LiteralPath (Join-Path $__dotfiles_dir 'bin/bash.exe') -PathType Leaf) {
                    $env:DIRENV_BASH = Join-Path $__dotfiles_dir 'bin\bash.exe'
                }
                $__dotfiles_dir = Split-Path -Parent $__dotfiles_dir
            }
            if ($env:DIRENV_BASH) { break }
        }
    }

    . ([scriptblock]::Create((& direnv hook pwsh) -join "`n"))
    $env:DIRENV_WARN_TIMEOUT = '60s'
    $__dotfiles_direnv = $true

    # direnv's pwsh hook only runs when the location changes, so a new, edited
    # or newly allowed .envrc in the current directory waits for a cd. zsh's
    # runs before every prompt, so the prompt (30-prompt.ps1) calls this too,
    # which also loads the directory the shell starts in. ~30 ms a prompt, for
    # the direnv process; it prints nothing when nothing changed.
    $DirenvPath = (Get-Command direnv -CommandType Application | Select-Object -First 1).Source
    function Update-DirenvEnvironment {
        $export = (& $DirenvPath export pwsh) -join [Environment]::NewLine
        if ($export) {
            . ([scriptblock]::Create($export))
        }
    }

    Remove-Variable -Name hook, currentAction, __dotfiles_git, __dotfiles_dir, __dotfiles_i -ErrorAction SilentlyContinue
}
