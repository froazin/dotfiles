# Generated tab completion for optional tools, cached like zsh's
# zcache_completion: each tool's completion script is generated once, and again
# only when its binary is newer than the cache.

$PwshCompletionDir = Join-Path $(
    if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA }
    elseif ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME }
    else { Join-Path $HOME '.local/share' }
) 'powershell/completions'

# Name, the arguments that print its PowerShell completion, and whether to load
# it on the first Tab rather than at startup. Lazy only suits a script that
# just registers a native completer: one that defines functions (op's) must be
# dot-sourced here, in the profile's scope. uv's takes ~200 ms to load.
# Patch, when there is one, edits the generated text, like zsh's
# _zcache_patch_<name>.
$PwshOptionalCompletions = @(
    @{ Name = 'uv'; Arguments = @('generate-shell-completion', 'powershell'); Lazy = $true }
    @{ Name = 'uvx'; Arguments = @('--generate-shell-completion', 'powershell'); Lazy = $true }
    @{
        Name = 'op'
        Arguments = @('completion', 'powershell')
        Lazy = $false
        # Cobra's script redirects Invoke-Expression rather than the op call
        # inside it, so op's "Completion ended with directive" lands on the
        # console on every Tab.
        Patch = {
            param([string]$Text)
            $Text.Replace('Invoke-Expression -OutVariable out "$RequestComp" 2>&1 | Out-Null', 'Invoke-Expression -OutVariable out "$RequestComp 2>`$null" | Out-Null')
        }
    }
)

# Returns 0 regenerated, 1 already current, 2 tool not installed, 3 generation
# failed; Update-ShellCompletion reports these.
function Update-PwshCompletionCache {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [scriptblock]$Patch,
        [switch]$Force
    )

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return 2
    }

    # The binary's own time, not a WinGet link's.
    $binary = Get-Item -LiteralPath $command.Source -Force
    $target = @($binary.Target) | Where-Object { $_ } | Select-Object -First 1
    if ($target) {
        $resolved = Join-Path (Split-Path -Parent $binary.FullName) $target
        if ([IO.Path]::IsPathRooted($target)) { $resolved = $target }
        $linked = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
        if ($linked) { $binary = $linked }
    }

    $file = Join-Path $PwshCompletionDir "$Name.ps1"
    # Outside the cache's *.ps1, so nothing ever loads it.
    $failed = Join-Path $PwshCompletionDir ".failed/$Name"

    if (-not $Force) {
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).LastWriteTimeUtc -ge $binary.LastWriteTimeUtc) {
            return 1
        }
        # Don't rerun a generator that failed for this same binary on every
        # startup; Update-ShellCompletion forces a retry.
        if ((Test-Path -LiteralPath $failed) -and (Get-Item -LiteralPath $failed).LastWriteTimeUtc -ge $binary.LastWriteTimeUtc) {
            return 3
        }
    }

    $null = New-Item -ItemType Directory -Force -Path (Join-Path $PwshCompletionDir '.failed')
    $tmp = "$file.new.$PID"
    $errors = "$tmp.err"
    try {
        # Run from a directory we own, so a tool that reads its working
        # directory never acts on the project the shell opened in. The output
        # goes straight to the file, byte for byte.
        $process = Start-Process -FilePath $command.Source -ArgumentList $Arguments -WorkingDirectory $PwshCompletionDir `
            -RedirectStandardOutput $tmp -RedirectStandardError $errors -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0 -and (Get-Item -LiteralPath $tmp).Length -gt 0) {
            if ($Patch) {
                $text = & $Patch ([IO.File]::ReadAllText($tmp))
                [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
            }
            Move-Item -LiteralPath $tmp -Destination $file -Force
            Remove-Item -LiteralPath $failed -Force -ErrorAction SilentlyContinue
            return 0
        }
    } catch {
        $null = $_
    } finally {
        Remove-Item -LiteralPath $tmp, $errors -Force -ErrorAction SilentlyContinue
    }

    $null = New-Item -ItemType File -Force -Path $failed
    return 3
}

# Registers a stand-in completer that loads the real one on the first Tab, then
# asks PowerShell to complete the same input again, which reaches the real one.
function Register-PwshLazyCompletion {
    # $File is used inside the closure. TabExpansion2 is in every PowerShell
    # 7, the only one that loads this profile.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'File')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '')]
    param([string]$Name, [string]$File)

    # Once only: if the script didn't replace this completer, completing again
    # would come straight back here.
    $state = @{ Loaded = $false }
    $loader = {
        param($wordToComplete, $commandAst, $cursorPosition)

        $null = $wordToComplete
        if ($state.Loaded) {
            return
        }
        $state.Loaded = $true
        . $File
        $root = $commandAst
        while ($root.Parent) { $root = $root.Parent }
        (TabExpansion2 -inputScript $root.Extent.Text -cursorColumn $cursorPosition).CompletionMatches
    }.GetNewClosure()

    Register-ArgumentCompleter -Native -CommandName $Name -ScriptBlock $loader
}

foreach ($__dotfiles_completion in $PwshOptionalCompletions) {
    if ((Update-PwshCompletionCache -Name $__dotfiles_completion.Name -Arguments $__dotfiles_completion.Arguments -Patch $__dotfiles_completion.Patch) -le 1) {
        $__dotfiles_file = Join-Path $PwshCompletionDir "$($__dotfiles_completion.Name).ps1"
        if ($__dotfiles_completion.Lazy) {
            Register-PwshLazyCompletion -Name $__dotfiles_completion.Name -File $__dotfiles_file
        } else {
            . $__dotfiles_file
        }
    }
}

Remove-Variable -Name __dotfiles_completion, __dotfiles_file -ErrorAction SilentlyContinue
