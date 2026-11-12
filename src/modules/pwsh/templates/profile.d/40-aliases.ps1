# Small commands, like 40-aliases.zsh.

# Opens a file, folder or URL with its default app, like xdg-open's browse.
function browse {
    param([Parameter(Mandatory = $true)][string]$Target)

    Start-Process -FilePath $Target
}

# Signals that a long-running command finished:  Start-Sleep 10; alert
function alert {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'It writes to the terminal, like the bell.')]
    param()

    # First, before anything else changes them.
    $ok = $?
    $code = $LASTEXITCODE

    # The line that called alert, without its "; alert", "&& alert" or "|| alert".
    $command = "$($MyInvocation.Line)".Trim() -replace '\s*(;|&&|\|\|)\s*alert\s*$', ''

    $esc = [char]27
    Write-Host ([char]7) -NoNewline
    if ($ok) {
        Write-Host "$esc[38;2;42;206;132mdone$esc[0m " -NoNewline
    } else {
        $detail = if ($code) { " ($code)" } else { '' }
        Write-Host "$esc[38;2;224;27;36mfailed$detail$esc[0m " -NoNewline
    }
    Write-Host $command
}
