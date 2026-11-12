<#
Claude Code configuration for Windows: the PowerShell twin of bootstrap.sh.
install.ps1 dot-sources this file in a scope of its own and calls
Invoke-Bootstrap. See docs/claude/overview.md.
#>

# Optional: the versioning skill works out the next version with cz (commitizen).
$ClaudeOptionalDeps = @('cz')
$ClaudeSubdirs = @('agents', 'commands', 'skills', 'rules', 'output-styles', 'hooks')

function Write-ClaudeOptionalDependency {
    foreach ($cmd in $ClaudeOptionalDeps) {
        if (Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue) {
            Write-DotfilesLog debug "Found optional dependency: $cmd"
            continue
        }

        switch ($cmd) {
            'cz' { Write-DotfilesLog warning 'Optional dependency missing: cz is not installed (commitizen, for example with uv tool install commitizen). The versioning skill works out bumps by hand without it.' }
            default { Write-DotfilesLog warning "Optional dependency missing: $cmd is not installed." }
        }
    }
}

function New-ClaudeDirectory {
    param([string]$ClaudeDir)

    # No chmod 700: a new directory under the profile inherits its ACL, which
    # already keeps other users out.
    if (-not (Initialize-Directory $ClaudeDir)) {
        return $false
    }

    $failed = $false
    foreach ($subdir in $ClaudeSubdirs) {
        if (-not (Initialize-Directory (Join-Path $ClaudeDir $subdir))) {
            $failed = $true
        }
    }

    return -not $failed
}

# Copies every file under $Root to the same place under $ClaudeDir, except
# the JSON files that are merged, the top-level directories in $Skip, and any
# file $Overlay has at the same relative path: that one replaces it.
function Install-ClaudeTemplate {
    param([string]$Root, [string]$ClaudeDir, [string[]]$Skip = @(), [string]$Overlay)

    $failed = $false
    $Root = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')

    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length + 1)
        if ($relative -eq 'settings.json' -or $relative -eq 'keybindings.json') {
            continue
        }
        if ($Skip -contains ($relative -split '[\\/]')[0]) {
            continue
        }
        if ($Overlay -and (Test-Path -LiteralPath (Join-Path $Overlay $relative) -PathType Leaf)) {
            continue
        }
        if ($file.Extension -eq '.pyc' -or $relative -match '(^|[\\/])__pycache__[\\/]') {
            continue
        }

        if (-not (Install-File $file.FullName (Join-Path $ClaudeDir $relative))) {
            $failed = $true
        }
    }

    return -not $failed
}

# The JSON type of a value from ConvertFrom-Json.
function Get-ClaudeJsonKind {
    param($Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return 'boolean' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return 'object' }
    if ($Value -is [array]) { return 'array' }
    return 'number'
}

# jq's ==: objects compare regardless of key order, and true never equals 1.
function Test-ClaudeJsonEqual {
    param($A, $B)

    $kind = Get-ClaudeJsonKind $A
    if ($kind -ne (Get-ClaudeJsonKind $B)) {
        return $false
    }

    switch ($kind) {
        'null' { return $true }
        'string' { return $A -ceq $B }
        'array' {
            if ($A.Count -ne $B.Count) {
                return $false
            }
            for ($i = 0; $i -lt $A.Count; $i++) {
                if (-not (Test-ClaudeJsonEqual $A[$i] $B[$i])) {
                    return $false
                }
            }
            return $true
        }
        'object' {
            $aProps = @($A.PSObject.Properties)
            if ($aProps.Count -ne @($B.PSObject.Properties).Count) {
                return $false
            }
            foreach ($p in $aProps) {
                $other = $B.PSObject.Properties[$p.Name]
                if ($null -eq $other -or -not (Test-ClaudeJsonEqual $p.Value $other.Value)) {
                    return $false
                }
            }
            return $true
        }
        default { return $A -eq $B }
    }
}

function Test-ClaudeJsonContain {
    param([object[]]$Array, $Value)

    foreach ($item in $Array) {
        if (Test-ClaudeJsonEqual $item $Value) {
            return $true
        }
    }

    return $false
}

# A copy of an object's properties, in order, so a merge never changes its inputs.
function Copy-ClaudeJsonObject {
    param($Object)

    $copy = New-Object PSObject
    foreach ($p in $Object.PSObject.Properties) {
        $copy.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList $p.Name, $p.Value))
    }

    return $copy
}

function Set-ClaudeJsonProperty {
    param($Object, [string]$Name, $Value)

    $existing = $Object.PSObject.Properties[$Name]
    if ($existing) {
        $existing.Value = $Value
    } else {
        $Object.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList $Name, $Value))
    }
}

# Template values win, objects merge key by key and arrays are unioned, as
# merge() in bootstrap.sh. Every return is ",$x" so arrays are never unrolled.
function Merge-ClaudeJsonValue {
    param($Current, $Template)

    $currentKind = Get-ClaudeJsonKind $Current
    $templateKind = Get-ClaudeJsonKind $Template

    if ($currentKind -eq 'object' -and $templateKind -eq 'object') {
        $result = Copy-ClaudeJsonObject $Current
        foreach ($p in $Template.PSObject.Properties) {
            $existing = $result.PSObject.Properties[$p.Name]
            # Not "$old = if ...": an if statement's output is unrolled, so a
            # one-item array would become its item and the template's would win.
            $old = $null
            if ($existing) { $old = $existing.Value }
            Set-ClaudeJsonProperty -Object $result -Name $p.Name -Value (Merge-ClaudeJsonValue $old $p.Value)
        }
        return , $result
    }

    if ($currentKind -eq 'array' -and $templateKind -eq 'array') {
        $result = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Current) { $result.Add($item) }
        foreach ($item in $Template) {
            if (-not (Test-ClaudeJsonContain $Current $item)) {
                $result.Add($item)
            }
        }
        return , $result.ToArray()
    }

    return , $Template
}

# merge_by() in bootstrap.sh: each template object merges into the first
# existing one with the same $Key, or is appended.
function Merge-ClaudeJsonByKey {
    param([object[]]$Current, [object[]]$Template, [string]$Key)

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Current) { $result.Add($item) }

    foreach ($item in $Template) {
        $id = Get-ClaudeJsonProperty $item $Key
        $index = -1
        for ($i = 0; $i -lt $result.Count; $i++) {
            $otherId = Get-ClaudeJsonProperty $result[$i] $Key
            if (Test-ClaudeJsonEqual $otherId $id) {
                $index = $i
                break
            }
        }

        if ($index -lt 0) {
            $result.Add($item)
        } else {
            $result[$index] = Merge-ClaudeJsonValue $result[$index] $item
        }
    }

    return , $result.ToArray()
}

function Get-ClaudeJsonProperty {
    param($Object, [string]$Name)

    if ((Get-ClaudeJsonKind $Object) -ne 'object') {
        return $null
    }

    $p = $Object.PSObject.Properties[$Name]
    if ($p) {
        return , $p.Value
    }

    return $null
}

# A value to iterate as jq's ".[]?" would: an array's items, nothing for null,
# else the value itself. Assign the result; @(...) around a call would wrap it.
function Get-ClaudeJsonArray {
    param($Value)

    $kind = Get-ClaudeJsonKind $Value
    if ($kind -eq 'array') {
        return , $Value
    }
    if ($kind -eq 'null') {
        return , @()
    }

    return , @($Value)
}

# CLAUDE_JSON_MERGE in bootstrap.sh, for two parsed files.
function Merge-ClaudeJson {
    param($Current, $Template)

    $result = Merge-ClaudeJsonValue $Current $Template

    # A union would keep an outdated copy of a template hook next to the new
    # one, so existing hooks with a template command are replaced instead.
    $templateHooks = Get-ClaudeJsonProperty $Template 'hooks'
    if ((Get-ClaudeJsonKind $templateHooks) -eq 'object') {
        $currentHooks = Get-ClaudeJsonProperty $Current 'hooks'
        $resultHooks = Get-ClaudeJsonProperty $result 'hooks'

        foreach ($hookEvent in $templateHooks.PSObject.Properties) {
            $templateEntries = Get-ClaudeJsonArray $hookEvent.Value
            $commands = New-Object System.Collections.Generic.List[object]
            foreach ($entry in $templateEntries) {
                foreach ($hook in (Get-ClaudeJsonArray (Get-ClaudeJsonProperty $entry 'hooks'))) {
                    $commands.Add((Get-ClaudeJsonProperty $hook 'command'))
                }
            }

            $kept = New-Object System.Collections.Generic.List[object]
            foreach ($entry in (Get-ClaudeJsonArray (Get-ClaudeJsonProperty $currentHooks $hookEvent.Name))) {
                if ((Get-ClaudeJsonKind $entry) -ne 'object') {
                    continue
                }
                $hooks = New-Object System.Collections.Generic.List[object]
                foreach ($hook in (Get-ClaudeJsonArray (Get-ClaudeJsonProperty $entry 'hooks'))) {
                    if (-not (Test-ClaudeJsonContain $commands.ToArray() (Get-ClaudeJsonProperty $hook 'command'))) {
                        $hooks.Add($hook)
                    }
                }
                if ($hooks.Count -gt 0) {
                    $copy = Copy-ClaudeJsonObject $entry
                    Set-ClaudeJsonProperty -Object $copy -Name hooks -Value $hooks.ToArray()
                    $kept.Add($copy)
                }
            }
            foreach ($entry in $templateEntries) { $kept.Add($entry) }

            Set-ClaudeJsonProperty -Object $resultHooks -Name $hookEvent.Name -Value $kept.ToArray()
        }
    }

    # A union would likewise add a second block for a context whenever the
    # template block changes, so keybindings merge block by context.
    if ((Get-ClaudeJsonKind $Template) -eq 'object' -and $Template.PSObject.Properties['bindings']) {
        $currentBindings = Get-ClaudeJsonProperty $Current 'bindings'
        # jq's "// []": null and false count as missing.
        if ($null -eq $currentBindings -or ($currentBindings -is [bool] -and -not $currentBindings)) {
            $currentBindings = @()
        } elseif ((Get-ClaudeJsonKind $currentBindings) -ne 'array') {
            throw 'bindings is not an array'
        }
        $merged = Merge-ClaudeJsonByKey -Current $currentBindings -Template (Get-ClaudeJsonArray $Template.bindings) -Key context
        Set-ClaudeJsonProperty -Object $result -Name bindings -Value $merged
    }

    return , $result
}

function ConvertFrom-ClaudeJson {
    param([string]$Text)

    # -DateKind is new in PowerShell 7.5. Without it, 7.0 to 7.4 turn
    # date-like strings into dates. 5.1 never does. -NoEnumerate (7.0) keeps
    # a top-level array an array, so [{...}] is refused as jq refuses it,
    # rather than read as the object inside; 5.1 never enumerates.
    $options = @{ InputObject = $Text; ErrorAction = 'Stop' }
    $parameters = (Get-Command ConvertFrom-Json).Parameters
    if ($parameters.ContainsKey('DateKind')) {
        $options['DateKind'] = 'String'
    }
    if ($parameters.ContainsKey('NoEnumerate')) {
        $options['NoEnumerate'] = $true
    }

    return , (ConvertFrom-Json @options)
}

function ConvertTo-ClaudeJson {
    param($Value)

    $json = ConvertTo-Json -InputObject $Value -Depth 100
    return ($json -replace "`r`n", "`n") + "`n"
}

function Read-ClaudeTemplateJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-DotfilesLog error "Template not found: <$Path>."
        return $null
    }

    try {
        return , (ConvertFrom-ClaudeJson ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath)))
    } catch {
        Write-DotfilesLog error "Failed to read the template <$Path>: $(("$($_.Exception.Message)" -split "`r?`n")[0])"
        return $null
    }
}

# The settings template with its hooks swapped for the PowerShell ones.
function Get-ClaudeSettingsTemplate {
    param([string]$Templates, [string]$Windows)

    $settings = Read-ClaudeTemplateJson (Join-Path $Templates 'settings.json')
    $windowsSettings = Read-ClaudeTemplateJson (Join-Path $Windows 'settings.json')
    if ($null -eq $settings -or $null -eq $windowsSettings) {
        return $null
    }

    Set-ClaudeJsonProperty -Object $settings -Name hooks -Value $windowsSettings.hooks
    return , $settings
}

# Merges $Template (parsed) into $Destination, as claude_merge_json in
# bootstrap.sh does with jq. $Source names the template in log messages.
function Merge-ClaudeJsonFile {
    param($Template, [string]$Source, [string]$Destination)

    if ($null -eq $Template) {
        return $false
    }

    if (Test-LinkPath $Destination) {
        Write-DotfilesLog warning "Existing file <$Destination> is a symbolic link and will be left alone."
        return $false
    }

    $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($item -and ($item -isnot [IO.FileInfo] -or ($item.Length -gt 0 -and $item.IsReadOnly))) {
        Write-DotfilesLog warning "Existing file <$Destination> is read-only and will be left alone."
        return $false
    }

    $created = -not $item -or $item.Length -eq 0
    try {
        $currentText = if ($created) { '' } else { [IO.File]::ReadAllText($item.FullName) }

        # Missing, empty or whitespace only: holds no values, so the template
        # replaces it.
        if ($currentText.Trim().Length -eq 0) {
            $merged = $Template
        } else {
            $current = ConvertFrom-ClaudeJson $currentText
            if ((Get-ClaudeJsonKind $current) -ne 'object') {
                throw 'not a single JSON object'
            }
            $merged = Merge-ClaudeJson $current $Template
        }
        $text = ConvertTo-ClaudeJson $merged
    } catch {
        $reason = ("$($_.Exception.Message)" -split "`r?`n")[0]
        Write-DotfilesLog error "Failed to merge <$Source> into <$Destination>, which was left unchanged: $reason"
        return $false
    }

    if ($text -ceq $currentText) {
        Write-DotfilesLog debug "<$Destination> is already up to date."
        return $true
    }

    if (-not (Initialize-Directory (Split-Path -Parent $Destination))) {
        return $false
    }

    $tmp = "$Destination.dotfiles.$PID"
    try {
        [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $Destination -Force -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Write-DotfilesLog error "Failed to write <$Destination>."
        return $false
    }

    if ($created) {
        Write-DotfilesLog info "Claude Code configuration created at <$Destination>."
    } else {
        Write-DotfilesLog info "Merged dotfiles configuration into <$Destination>."
    }
    return $true
}

function Install-ClaudeConfig {
    Write-DotfilesLog info 'Installing Claude Code configuration.'

    $templates = Join-Path $PSScriptRoot 'templates'
    $windows = Join-Path $PSScriptRoot 'windows'
    $claudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $failed = $false

    if (-not (New-ClaudeDirectory $claudeDir)) { $failed = $true }

    # The shared templates, with windows/ laid over them: the PowerShell hooks
    # in place of the sh and Python ones, and Windows copies of files that say
    # something different there, such as the commit-signing rule, which has no
    # guard hook behind it on Windows.
    if (-not (Install-ClaudeTemplate -Root $templates -ClaudeDir $claudeDir -Skip 'hooks' -Overlay $windows)) { $failed = $true }
    if (-not (Install-ClaudeTemplate -Root $windows -ClaudeDir $claudeDir)) { $failed = $true }

    $settings = Get-ClaudeSettingsTemplate -Templates $templates -Windows $windows
    if (-not (Merge-ClaudeJsonFile -Template $settings -Source (Join-Path $templates 'settings.json') -Destination (Join-Path $claudeDir 'settings.json'))) { $failed = $true }

    $keybindingsPath = Join-Path $templates 'keybindings.json'
    $keybindings = Read-ClaudeTemplateJson $keybindingsPath
    if (-not (Merge-ClaudeJsonFile -Template $keybindings -Source $keybindingsPath -Destination (Join-Path $claudeDir 'keybindings.json'))) { $failed = $true }

    if ($failed) {
        return $false
    }

    Write-DotfilesLog info "Claude Code configuration installed to <$claudeDir>."
    return $true
}

function Invoke-Bootstrap {
    $errors = $false

    Write-DotfilesLog info 'Bootstrapping Claude Code configuration.'

    Write-ClaudeOptionalDependency

    if (-not (Install-ClaudeConfig)) {
        Write-DotfilesLog error 'Failed to install Claude Code configuration.'
        $errors = $true
    }

    if ($errors) {
        Write-DotfilesLog warning 'Claude Code configuration completed with errors.'
        return $false
    }

    Write-DotfilesLog info 'Claude Code configuration bootstrapped successfully.'
    return $true
}
