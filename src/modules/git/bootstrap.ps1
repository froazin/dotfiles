<#
Global gitignore for Windows: the PowerShell twin of bootstrap.sh.
install.ps1 dot-sources this file in a scope of its own and calls
Invoke-Bootstrap. See docs/git-module.md.
#>

function New-GitExcludesFile {
    Write-DotfilesLog info 'Configuring global gitignore file.'

    # --get exits 1 when the key is unset, which is not an error here.
    $excludesFile = & git config --global --type=path --get core.excludesfile 2> $null
    $status = $LASTEXITCODE
    if ($status -ne 0 -and $status -ne 1) {
        Write-DotfilesLog error 'Failed to read global core.excludesfile.'
        return $false
    }

    $excludesFile = "$($excludesFile | Select-Object -Last 1)".Trim()
    if (-not $excludesFile) {
        # Forward slashes, which git and Git Bash read as they are.
        $excludesFile = (Join-Path $HOME '.gitignore') -replace '\\', '/'
        Write-DotfilesLog debug "No existing git configuration for global core.excludesfile was found, a new one will be generated at <$excludesFile>."

        $null = & git config --global core.excludesfile $excludesFile 2> $null
        if ($LASTEXITCODE -ne 0) {
            Write-DotfilesLog error "Failed to set global core.excludesfile to <$excludesFile>."
            return $false
        }
    }

    if (-not (Install-File (Join-Path $PSScriptRoot 'templates/.gitignore') $excludesFile)) {
        return $false
    }

    Write-DotfilesLog info "Global gitignore file installed at <$excludesFile>."
    return $true
}

function Invoke-Bootstrap {
    $errors = $false

    Write-DotfilesLog info 'Bootstrapping git configuration.'

    if (-not (New-GitExcludesFile)) {
        Write-DotfilesLog error 'Failed to create gitignore file.'
        $errors = $true
    }

    if ($errors) {
        Write-DotfilesLog warning 'Git configuration completed with errors.'
        return $false
    }

    Write-DotfilesLog info 'Git configuration bootstrapped successfully.'
    return $true
}
