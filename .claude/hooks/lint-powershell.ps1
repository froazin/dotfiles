# Called by lint-shell.sh for an edited .ps1 or .psd1 file: prints parse
# errors, then PSScriptAnalyzer's findings with the repository's settings when
# the module is installed. Prints nothing when the file is clean.
param([Parameter(Mandatory = $true)][string]$Path)

$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
foreach ($e in $errors) {
    Write-Output "${Path}:$($e.Extent.StartLineNumber): $($e.Message)"
}

if (-not $errors -and (Get-Module -ListAvailable PSScriptAnalyzer)) {
    $settings = Join-Path $PSScriptRoot '../../PSScriptAnalyzerSettings.psd1'
    foreach ($f in Invoke-ScriptAnalyzer -Path $Path -Settings $settings) {
        Write-Output "${Path}:$($f.Line): $($f.RuleName): $($f.Message)"
    }
}
