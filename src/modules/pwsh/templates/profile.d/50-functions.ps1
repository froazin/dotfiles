# A workspace is a git repository at <provider>/<org>/<repo> under
# $env:WORKSPACE_DIR, default ~/workspaces.

function __ws_root {
    if ($env:WORKSPACE_DIR) {
        return $env:WORKSPACE_DIR
    }

    return (Join-Path $HOME 'workspaces')
}

# One line per workspace: <provider>/<org>/<repo>, a tab, then its full path.
function __ws_list {
    $root = __ws_root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return
    }

    $lines = foreach ($provider in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($provider.Name -eq '$RECYCLE.BIN') { continue }
        foreach ($org in @(Get-ChildItem -LiteralPath $provider.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($org.Name -eq '$RECYCLE.BIN') { continue }
            foreach ($repo in @(Get-ChildItem -LiteralPath $org.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                "$($provider.Name)/$($org.Name)/$($repo.Name)`t$($repo.FullName)"
            }
        }
    }

    $lines | Sort-Object
}

# The *.code-workspace to open, preferring <dir>/<dir name>.code-workspace,
# or nothing when there is none.
function __ws_code_target {
    param([string]$Dir)

    $candidates = @(Get-ChildItem -LiteralPath $Dir -Filter '*.code-workspace' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($candidates.Count -eq 0) {
        return $null
    }

    $preferred = Join-Path $Dir ((Split-Path -Leaf $Dir) + '.code-workspace')
    if (Test-Path -LiteralPath $preferred -PathType Leaf) {
        return $preferred
    }

    return $candidates[0].FullName
}

function __ws_is_elevated {
    if ($env:OS -eq 'Windows_NT') {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    return ("$(& id -u 2> $null)" -eq '0')
}

function Enter-Workspace {
    <#
    .SYNOPSIS
    Goes to a workspace, a git repository at <provider>/<org>/<repo> under $env:WORKSPACE_DIR (default ~/workspaces).

    .DESCRIPTION
    With no query, picks a workspace with fzf. With a query, goes straight there if it matches exactly one.
    Aliases: ws, workspace, workspaces. wsc is ws -Code.

    .PARAMETER Code
    Also opens the workspace in VS Code: a *.code-workspace file at its root if there is one, otherwise the directory.

    .PARAMETER Help
    Shows the usage.

    .PARAMETER Query
    The fzf query to start with.

    .EXAMPLE
    ws dotfiles

    .EXAMPLE
    ws -c
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Alias('c')]
        [switch]$Code,

        [Alias('h')]
        [switch]$Help,

        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Query
    )

    # The zsh spellings too, so the same muscle memory works.
    $words = New-Object System.Collections.Generic.List[string]
    $options = $true
    foreach ($word in $Query) {
        if ($options -and $word -eq '--code') { $Code = $true; continue }
        if ($options -and $word -eq '--help') { $Help = $true; continue }
        if ($options -and $word -eq '--') { $options = $false; continue }
        if ($options -and $word -like '--?*') {
            Write-Error "Unknown option: $word"
            return
        }
        $words.Add($word)
    }

    if ($Help) {
        'usage: ws [-c|-Code] [query]'
        '  no query   pick a workspace with fzf'
        '  query      jump straight there if it matches exactly one'
        '  -c         also open the workspace in VS Code - a'
        '             *.code-workspace file at its root if there is'
        '             one, otherwise the directory itself'
        return
    }

    $root = __ws_root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Error 'The Workspaces directory does not exist. Please create it to use this function.'
        return
    }

    if (-not (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Error 'fzf is not installed. Please install it to use this function.'
        return
    }

    # The preview runs in pwsh, with fzf quoting {2} (the full path) for it,
    # and writes UTF-8, which is what fzf reads.
    $preview = '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Write-Output {2}; Write-Output ""; if (Get-Command git -ErrorAction Ignore) { git -C {2} status -sb 2>$null; Write-Output ""; git -C {2} log --oneline -10 2>$null }'
    $fzfArgs = @(
        "--query=$($words -join ' ')"
        '--select-1'
        '--exit-0'
        '--layout=reverse'
        '--prompt=workspace> '
        "--delimiter=`t"
        '--with-nth=1'
        '--with-shell=pwsh -NoLogo -NoProfile -NonInteractive -Command'
        "--preview=$preview"
        '--preview-window=right,55%,wrap'
    )

    # fzf reads and writes UTF-8, which Windows PowerShell and the console
    # don't use by default.
    $savedOutputEncoding = $OutputEncoding
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        $OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        $selection = __ws_list | & fzf @fzfArgs
    } finally {
        $OutputEncoding = $savedOutputEncoding
        [Console]::OutputEncoding = $savedConsoleEncoding
    }

    $target = if ($selection) { ("$(@($selection)[0])" -split "`t", 2)[-1] } else { $null }
    if (-not $target -or -not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Error 'Invalid workspace selected or workspace does not exist.'
        return
    }

    try {
        Set-Location -LiteralPath $target -ErrorAction Stop
    } catch {
        Write-Error "Failed to change directory to $target"
        return
    }

    if (-not $Code) {
        return
    }

    # As in zsh: no VS Code for an administrator outside a dev container.
    if ((__ws_is_elevated) -and $env:REMOTE_CONTAINERS -ne 'true') {
        Write-Error 'Not opening VS Code as an administrator.'
        return
    }

    if (-not (Get-Command code -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Error "'code' is not on PATH."
        return
    }

    $codeTarget = __ws_code_target $target
    if ($codeTarget) {
        Write-Information "ws: opening $(Split-Path -Leaf $codeTarget)" -InformationAction Continue
    } else {
        $codeTarget = $target
    }

    & code $codeTarget
}

function wsc {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Query
    )

    Enter-Workspace -Code -Query $Query
}

Set-Alias -Name workspaces -Value Enter-Workspace
Set-Alias -Name workspace -Value Enter-Workspace
Set-Alias -Name ws -Value Enter-Workspace

Register-ArgumentCompleter -CommandName Enter-Workspace, wsc -ParameterName Query -ScriptBlock {
    # The third of the five arguments PowerShell passes is the word to complete.
    $wordToComplete = $args[2]
    $word = [WildcardPattern]::Escape("$wordToComplete".Trim([char[]]"'`""))
    foreach ($line in @(__ws_list)) {
        $name = ($line -split "`t", 2)[0]
        if ($name -like "*$word*") {
            New-Object System.Management.Automation.CompletionResult -ArgumentList $name, $name, 'ParameterValue', $name
        }
    }
}
