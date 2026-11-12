<#
PowerShell 7 profile: profile.ps1 and its numbered profile.d drop-ins.
install.ps1 dot-sources this file in a scope of its own and calls
Invoke-Bootstrap. See docs/pwsh-module.md.
#>

$PwshSoftDeps = @('fzf')
$PwshOptionalDeps = @('git', 'code', 'uv', 'op', 'direnv')

function Test-PwshSoftDependency {
    $failed = $false

    foreach ($cmd in $PwshSoftDeps) {
        if (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue) {
            Write-DotfilesLog debug "Found soft dependency: $cmd"
        } else {
            Write-DotfilesLog error "Missing dependency: $cmd is not installed. The configuration will be installed, but the features that rely on it stay inert until it is."
            $failed = $true
        }
    }

    return -not $failed
}

function Write-PwshOptionalDependency {
    foreach ($cmd in $PwshOptionalDeps) {
        if (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue) {
            Write-DotfilesLog info "Optional integration enabled: $cmd"
        } else {
            Write-DotfilesLog warning "Optional integration skipped: $cmd is not installed. Its shell integration stays dormant until it is, no reinstall needed."
        }
    }
}

# Asks pwsh rather than reading $PROFILE, which is Windows PowerShell's when
# this runs there, and which follows a Documents folder moved by OneDrive.
function Get-PwshProfilePath {
    $path = & pwsh -NoLogo -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserAllHosts' 2> $null
    $path = "$($path | Select-Object -Last 1)".Trim()

    if ($LASTEXITCODE -ne 0 -or -not $path -or -not [IO.Path]::IsPathRooted($path)) {
        Write-DotfilesLog error 'Failed to find the PowerShell 7 profile path with pwsh.'
        return $null
    }

    return $path
}

function Install-PwshConfig {
    Write-DotfilesLog info 'Installing PowerShell configuration.'

    $profilePath = Get-PwshProfilePath
    if (-not $profilePath) {
        return $false
    }

    $templates = Join-Path $PSScriptRoot 'templates'
    $profileDir = Split-Path -Parent $profilePath
    $failed = $false

    if (-not (Install-File (Join-Path $templates 'profile.ps1') $profilePath)) {
        $failed = $true
    }

    foreach ($template in @(Get-ChildItem -LiteralPath (Join-Path $templates 'profile.d') -Filter '*.ps1' -File | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object Name)) {
        if (-not (Install-File $template.FullName (Join-Path $profileDir "profile.d/$($template.Name)"))) {
            $failed = $true
        }
    }

    if ($failed) {
        if (Test-PwshControlledFolderAccess) {
            Write-DotfilesLog error "Controlled folder access is on, and probably stopped PowerShell writing to <$profileDir>: Windows Security shows ""Protected folder access blocked"". Rather than allow PowerShell to change protected folders for good, turn Controlled folder access off (Windows Security > Virus & threat protection > Ransomware protection), run the installer again, then turn it back on."
        }
        return $false
    }

    Write-DotfilesLog info "PowerShell configuration installed to <$profileDir>."
    return $true
}

# Windows Security's Controlled folder access protects Documents, where the
# profile lives, from any program not on its allow list. 1 is on; 2 is audit
# mode, which only logs. Readable without admin rights.
function Test-PwshControlledFolderAccess {
    try {
        return ((Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -eq 1)
    } catch {
        return $false
    }
}

function Invoke-Bootstrap {
    $errors = $false

    Write-DotfilesLog info 'Bootstrapping PowerShell configuration.'

    if (-not (Test-PwshSoftDependency)) { $errors = $true }
    Write-PwshOptionalDependency

    if (-not (Install-PwshConfig)) {
        Write-DotfilesLog error 'Failed to install PowerShell configuration.'
        $errors = $true
    }

    if ($errors) {
        Write-DotfilesLog warning 'PowerShell configuration completed with errors.'
        return $false
    }

    Write-DotfilesLog info 'PowerShell configuration bootstrapped successfully.'
    return $true
}
