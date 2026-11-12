#Requires -Version 5.1
<#
.SYNOPSIS
Installs the dotfiles for whoever runs it, on Windows.

.DESCRIPTION
Runs src/modules/<name>/bootstrap.ps1 for each module whose <name> is a command
on PATH, and exits 1 if any of them failed. The PowerShell twin of install.sh:
see docs/installer.md.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0

$DotfilesLogLevel = if ($env:DOTFILES_LOG_LEVEL) { $env:DOTFILES_LOG_LEVEL } else { 'info' }
$DotfilesLogFile = if ($env:DOTFILES_LOG_FILE) { $env:DOTFILES_LOG_FILE } else { Join-Path $HOME '.local/var/log/dotfiles.log' }

$DotfilesLogLevels = @{ trace = 0; debug = 1; info = 2; warning = 3; error = 4; fatal = 5 }
$DotfilesLogLabels = @('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')

function Get-LogLevelValue {
    param([string]$Level)

    $key = "$Level".ToLowerInvariant()
    if ($DotfilesLogLevels.ContainsKey($key)) {
        return $DotfilesLogLevels[$key]
    }

    return 9
}

function Write-LogToConsole {
    param([int]$Level, [string]$Message, [string]$Timestamp)

    if ([Console]::IsErrorRedirected) {
        return
    }

    $label = $DotfilesLogLabels[$Level]

    if (-not $Host.UI.SupportsVirtualTerminal) {
        [Console]::Error.WriteLine("$Timestamp [$label] $Message")
        return
    }

    $esc = [char]27
    $color = switch ($Level) {
        0 { "$esc[1;30m" } # grey
        1 { "$esc[1;33m" } # yellow
        2 { "$esc[1;36m" } # cyan
        3 { "$esc[1;33m" } # yellow
        4 { "$esc[1;31m" } # red
        default { "$esc[1;91m" } # bright red
    }

    [Console]::Error.WriteLine("$esc[0;32m$Timestamp $color[$label]$esc[0m $Message")
}

function Write-LogToFile {
    param([int]$Level, [string]$Message, [string]$Timestamp)

    # Not Initialize-Directory: its failure logs, which would recurse back here.
    try {
        $dir = Split-Path -Parent $DotfilesLogFile
        if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
            $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
        }

        $entry = [ordered]@{
            timestamp = $Timestamp
            level = $DotfilesLogLabels[$Level].ToLowerInvariant()
            message = $Message
        }
        $line = (ConvertTo-Json -InputObject $entry -Compress) + "`n"
        [IO.File]::AppendAllText($DotfilesLogFile, $line, (New-Object Text.UTF8Encoding $false))
    } catch {
        return
    }
}

function Write-DotfilesLog {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('trace', 'debug', 'info', 'warning', 'error', 'fatal')]
        [string]$Level,

        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [string]$Message
    )

    $value = Get-LogLevelValue $Level

    # Fatal exits even when the level hides it or the log file cannot be written.
    if ($value -ge (Get-LogLevelValue $DotfilesLogLevel)) {
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
        Write-LogToConsole -Level $value -Message $Message -Timestamp $timestamp
        Write-LogToFile -Level $value -Message $Message -Timestamp $timestamp
    }

    if ($value -ge 5) {
        exit 1
    }
}

function Initialize-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return $true
    }

    try {
        $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
    } catch {
        Write-DotfilesLog error "Failed to create directory <$Path>: $($_.Exception.Message)"
        return $false
    }

    return $true
}

function Test-LinkPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    # LinkType, not the ReparsePoint attribute: OneDrive's cloud files are
    # reparse points too, and must be treated as plain files.
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return [bool]($item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction'))
}

# Byte for byte, like cmp -s. .NET rather than Get-FileHash, which Windows
# PowerShell can't load when it inherits pwsh's PSModulePath, as it does when
# started from pwsh.
function Test-SameFile {
    param([string]$Left, [string]$Right)

    try {
        $a = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Left).ProviderPath)
        $b = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Right).ProviderPath)
    } catch {
        return $false
    }

    if ($a.Length -ne $b.Length) {
        return $false
    }
    for ($i = 0; $i -lt $a.Length; $i++) {
        if ($a[$i] -ne $b[$i]) {
            return $false
        }
    }
    return $true
}

function Install-File {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Source,
        [Parameter(Mandatory = $true, Position = 1)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-DotfilesLog error "Template not found: <$Source>."
        return $false
    }

    if (Test-LinkPath $Destination) {
        Write-DotfilesLog warning "Existing file <$Destination> is a symbolic link and will be left alone."
        return $false
    }

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $same = Test-SameFile $Source $Destination

        if ($same) {
            Write-DotfilesLog debug "<$Destination> is already up to date."
            return $true
        }

        Write-DotfilesLog warning "Existing file <$Destination> was found, it will be overwritten."
    }

    if (-not (Initialize-Directory (Split-Path -Parent $Destination))) {
        return $false
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    } catch {
        Write-DotfilesLog error "Failed to write <$Destination>: $($_.Exception.Message)"
        return $false
    }

    Write-DotfilesLog debug "Installed <$Destination>."
    return $true
}

function Invoke-Module {
    param([string]$Package, [string]$BootstrapFile)

    # A child scope per module: what one module defines never reaches the next.
    & {
        param($Package, $BootstrapFile)

        Write-DotfilesLog debug "Loading $Package configuration from $BootstrapFile."
        try {
            . $BootstrapFile
        } catch {
            Write-DotfilesLog error "Failed to load $Package configuration: $($_.Exception.Message)"
            return $false
        }

        if (-not (Get-Command Invoke-Bootstrap -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-DotfilesLog error "Failed to load $Package configuration: <$BootstrapFile> defines no Invoke-Bootstrap function."
            return $false
        }

        Write-DotfilesLog debug "Running $Package configuration."
        try {
            $result = Invoke-Bootstrap
        } catch {
            Write-DotfilesLog error "Failed to execute $Package configuration: $($_.Exception.Message)"
            return $false
        }

        if ($result -isnot [bool]) {
            Write-DotfilesLog error "Failed to execute $Package configuration: Invoke-Bootstrap returned something other than `$true or `$false."
            return $false
        }

        if (-not $result) {
            Write-DotfilesLog error "Failed to execute $Package configuration."
        }

        return $result
    } $Package $BootstrapFile
}

function Invoke-Main {
    $installErrors = $false

    Write-DotfilesLog info 'Bootstrapping dotfiles.'

    Write-DotfilesLog debug 'Searching for configurations.'
    foreach ($dir in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'modules') -Directory | Sort-Object Name)) {
        $package = $dir.Name
        Write-DotfilesLog debug "Found configuration $package"

        if (-not (Get-Command $package -CommandType Application -ErrorAction SilentlyContinue)) {
            Write-DotfilesLog debug "Skipping $package, as it is not installed."
            continue
        }

        $bootstrapFile = Join-Path $dir.FullName 'bootstrap.ps1'
        if (-not (Test-Path -LiteralPath $bootstrapFile -PathType Leaf)) {
            Write-DotfilesLog debug "Bootstrap file for $package not found."
            continue
        }

        if (-not (Invoke-Module -Package $package -BootstrapFile $bootstrapFile)) {
            $installErrors = $true
        }
    }

    if ($installErrors) {
        return $false
    }

    Write-DotfilesLog info 'Dotfiles configuration completed successfully.'
    return $true
}

# Dot-sourcing defines the helpers without installing anything, for tests.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Invoke-Main)) {
        Write-DotfilesLog warning 'Dotfiles configuration has completed with errors.'
        exit 1
    }

    exit 0
}
