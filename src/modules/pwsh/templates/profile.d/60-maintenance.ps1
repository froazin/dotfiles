# Profile maintenance, like zsh's zshup.

# Regenerates every cached completion in $PwshOptionalCompletions
# (10-completion.ps1), failed ones included, and reports each.
function Update-ShellCompletion {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    foreach ($completion in $PwshOptionalCompletions) {
        $status = Update-PwshCompletionCache -Name $completion.Name -Arguments $completion.Arguments -Patch $completion.Patch -Force
        $what = switch ($status) {
            0 { 'regenerated' }
            2 { 'skipped (not installed)' }
            3 { 'FAILED to generate' }
            default { 'unchanged' }
        }
        "  $($completion.Name)  $what"
    }

    '  open a new shell to load them'
}

Set-Alias -Name pwshup -Value Update-ShellCompletion
