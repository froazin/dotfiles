# The zsh prompt (30-prompt.zsh, a port of the devcontainers "common-utils"
# theme) for PowerShell, without oh-my-posh:
#
#   (venv) <logo> user[@host] -> dir (branch) $
#
# The git segment reads .git directly, so no git process runs per prompt. It
# shows the branch, or the short sha when HEAD is detached, and the operation
# in progress, as vcs_info's actionformats do: (main|rebase-i). There's no
# dirty marker on Windows, where git status is too slow to run on every prompt.

$PromptColors = @{
    User = '#2ACE84'     # username
    Ok = '#CCCCCC'       # arrow ok, trailing $, venv
    Error = '#E74856'    # arrow on failure, branch name
    Path = '#21BFD3'     # path
    Paren = '#6A6A6A'    # parens around the branch
    Logo = '#2671BE'     # PowerShell blue
    Dim = '#767676'      # Campbell bright black, for the logo when elevated
}

$PromptLogo = [char]::ConvertFromUtf32(0xF0A0A)   # nf-md-powershell
$PromptArrow = [string][char]0x279C               # heavy round-tipped rightwards arrow

$PromptElevated = if ($env:OS -eq 'Windows_NT') {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    "$(& id -u 2> $null)" -eq '0'
}

$PromptHost = if ($env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
    '@' + [Environment]::MachineName
} else {
    ''
}

function Format-PromptColor {
    param([string]$Color, [string]$Text)

    $esc = [char]27
    $r = [Convert]::ToInt32($Color.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($Color.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($Color.Substring(5, 2), 16)
    "$esc[38;2;${r};${g};${b}m$Text$esc[0m"
}

# The git directory for $Dir or the nearest directory above it, following a
# linked worktree's or a submodule's .git file. Nothing outside a repository.
function Get-PromptGitDir {
    param([string]$Dir)

    while ($Dir) {
        $dotGit = Join-Path $Dir '.git'
        if ([IO.Directory]::Exists($dotGit)) {
            return $dotGit
        }
        if ([IO.File]::Exists($dotGit)) {
            $line = [IO.File]::ReadAllText($dotGit).Trim()
            if ($line.StartsWith('gitdir:')) {
                $target = $line.Substring(7).Trim()
                if (-not [IO.Path]::IsPathRooted($target)) {
                    $target = Join-Path $Dir $target
                }
                return [IO.Path]::GetFullPath($target)
            }
            return $null
        }
        $Dir = [IO.Path]::GetDirectoryName($Dir)
    }

    return $null
}

# branch, branch|action, or the short sha of a detached HEAD.
function Get-PromptGitStatus {
    param([string]$GitDir)

    $head = [IO.File]::ReadAllText((Join-Path $GitDir 'HEAD')).Trim()
    $branch = if ($head.StartsWith('ref:')) {
        $head.Substring(4).Trim() -replace '^refs/heads/', ''
    } else {
        $head.Substring(0, [Math]::Min(7, $head.Length))
    }

    # A rebase detaches HEAD, so name the branch being rebased, as vcs_info
    # does.
    $action = $null
    $rebaseMerge = Join-Path $GitDir 'rebase-merge'
    $rebaseApply = Join-Path $GitDir 'rebase-apply'
    if ([IO.Directory]::Exists($rebaseMerge)) {
        $action = if ([IO.File]::Exists((Join-Path $rebaseMerge 'interactive'))) { 'rebase-i' } else { 'rebase-m' }
        $headName = Join-Path $rebaseMerge 'head-name'
        if ([IO.File]::Exists($headName)) {
            $branch = [IO.File]::ReadAllText($headName).Trim() -replace '^refs/heads/', ''
        }
    } elseif ([IO.Directory]::Exists($rebaseApply)) {
        $action = if ([IO.File]::Exists((Join-Path $rebaseApply 'rebasing'))) { 'rebase' }
        elseif ([IO.File]::Exists((Join-Path $rebaseApply 'applying'))) { 'am' }
        else { 'am/rebase' }
        $headName = Join-Path $rebaseApply 'head-name'
        if ([IO.File]::Exists($headName)) {
            $branch = [IO.File]::ReadAllText($headName).Trim() -replace '^refs/heads/', ''
        }
    } elseif ([IO.File]::Exists((Join-Path $GitDir 'MERGE_HEAD'))) {
        $action = 'merge'
    } elseif ([IO.File]::Exists((Join-Path $GitDir 'CHERRY_PICK_HEAD'))) {
        $action = 'cherry'
    } elseif ([IO.File]::Exists((Join-Path $GitDir 'BISECT_LOG'))) {
        $action = 'bisect'
    }

    if ($action) {
        return "$branch|$action"
    }
    return $branch
}

function prompt {
    # First, before anything else changes it.
    $ok = $?

    # direnv before every prompt, as in zsh (see 20-tools.ps1).
    if ($__dotfiles_direnv) {
        try {
            Update-DirenvEnvironment
        } catch {
            $null = $_
        }
    }

    $parts = New-Object System.Collections.Generic.List[string]

    if ($env:VIRTUAL_ENV) {
        $name = Split-Path -Leaf $env:VIRTUAL_ENV
        if ($name -eq '.venv' -or $name -eq 'venv') {
            $name = Split-Path -Leaf (Split-Path -Parent $env:VIRTUAL_ENV)
        }
        $parts.Add((Format-PromptColor $PromptColors.Ok "($name)"))
    }

    $logoColor = if ($PromptElevated) { $PromptColors.Dim } else { $PromptColors.Logo }
    $parts.Add((Format-PromptColor $logoColor $PromptLogo))
    $parts.Add((Format-PromptColor $PromptColors.User "$([Environment]::UserName)$PromptHost"))
    $parts.Add((Format-PromptColor $(if ($ok) { $PromptColors.Ok } else { $PromptColors.Error }) $PromptArrow))

    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    $path = $location.ProviderPath
    $dir = if ($location.Provider.Name -ne 'FileSystem') {
        $location.Path
    } elseif ($path.TrimEnd('\', '/') -eq $HOME.TrimEnd('\', '/')) {
        '~'
    } else {
        $leaf = Split-Path -Leaf $path
        if ($leaf) { $leaf } else { $path }
    }
    $parts.Add((Format-PromptColor $PromptColors.Path $dir))

    # Not on a network share (\\server\share, \\wsl$\...), where the reads can
    # stall, like zsh skipping /mnt.
    if ($location.Provider.Name -eq 'FileSystem' -and -not $path.StartsWith('\\')) {
        try {
            $gitDir = Get-PromptGitDir $path
            if ($gitDir) {
                $status = Get-PromptGitStatus $gitDir
                $parts.Add((Format-PromptColor $PromptColors.Paren '(') + (Format-PromptColor $PromptColors.Error $status) + (Format-PromptColor $PromptColors.Paren ')'))
            }
        } catch {
            $null = $_
        }
    }

    $parts.Add((Format-PromptColor $PromptColors.Ok $(if ($PromptElevated) { '#' } else { '$' })))

    ($parts -join ' ') + ' '
}
