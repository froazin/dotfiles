# PSScriptAnalyzer settings for every .ps1 in the repository. CI runs
# Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1,
# and the VS Code PowerShell extension reads this file from the workspace root.
@{
    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # An installer and its helpers change state by design, and nothing
        # calls them with -WhatIf.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        # PowerShell 7 first, but Windows PowerShell 5.1 must still run
        # everything: install.ps1, the modules and the claude hooks.
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleTypes = @{
            Enable = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }

        # Formatting, the same as the extension's OTBS preset.
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            Kind = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckSeparator = $true
            CheckInnerBrace = $true
            CheckPipe = $true
            CheckParameter = $false
        }
        PSAlignAssignmentStatement = @{
            Enable = $false
        }
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        # Off: in PSScriptAnalyzer 1.25.0 it makes about one run in three fail
        # with "Object reference not set to an instance of an object".
        PSUseCorrectCasing = @{
            Enable = $false
        }
    }
}
