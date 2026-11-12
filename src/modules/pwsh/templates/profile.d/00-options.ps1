# Environment and PSReadLine's basic options, like zsh's .zshenv and
# 00-options.zsh.

# Root of the <host>/<owner>/<repo> clones, exported so that everything
# started from this shell, Claude Code's hooks included, agrees with ws.
if (-not $env:WORKSPACE_DIR) {
    $env:WORKSPACE_DIR = Join-Path $HOME 'workspaces'
}

# As zsh, but only when EDITOR isn't set already: VS Code, except in an elevated
# session outside a dev container, then vim, then Notepad.
if (-not $env:EDITOR) {
    $__dotfiles_elevated = if ($env:OS -eq 'Windows_NT') {
        ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } else {
        "$(& id -u 2> $null)" -eq '0'
    }

    if ((Get-Command code -CommandType Application -ErrorAction SilentlyContinue) -and (-not $__dotfiles_elevated -or $env:REMOTE_CONTAINERS -eq 'true')) {
        $env:EDITOR = 'code --wait'
    } elseif (Get-Command vim -CommandType Application -ErrorAction SilentlyContinue) {
        $env:EDITOR = 'vim'
    } else {
        $env:EDITOR = 'notepad'
    }
    $env:VISUAL = $env:EDITOR

    Remove-Variable -Name __dotfiles_elevated -ErrorAction SilentlyContinue
}

# The prompt shows the virtualenv's name itself.
$env:VIRTUAL_ENV_DISABLE_PROMPT = '1'

if (Get-Module PSReadLine) {
    # Windows Terminal turns the bell into a taskbar flash.
    Set-PSReadLineOption -BellStyle None

    # History is per session and in memory only: nothing is ever written to
    # disk. A line starting with a space is never recorded.
    Set-PSReadLineOption -HistorySaveStyle SaveNothing -MaximumHistoryCount 50000 -HistoryNoDuplicates
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$Line)
        -not $Line.StartsWith(' ')
    }
}
