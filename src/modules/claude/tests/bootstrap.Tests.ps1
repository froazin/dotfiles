<#
Pester 5 tests for the claude module's Windows installer, bootstrap.ps1: its
port of CLAUDE_JSON_MERGE from bootstrap.sh (Merge-ClaudeJson and
Merge-ClaudeJsonFile), the settings it composes from templates/settings.json
and windows/settings.json, and Invoke-Bootstrap end to end. The merge rules are
in docs/claude/overview.md. Runs in PowerShell 7 and Windows PowerShell 5.1:

    Invoke-Pester -Path src/modules/claude/tests
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll and BeforeEach variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'The target profiles know only the Pester 3 that ships with Windows; these tests need Pester 5.')]
param()

Describe 'claude bootstrap.ps1' {
    BeforeAll {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).ProviderPath
        $moduleRoot = Join-Path $repoRoot 'src/modules/claude'
        $templatesDir = Join-Path $moduleRoot 'templates'
        $windowsDir = Join-Path $moduleRoot 'windows'

        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('claude-bootstrap-tests-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $testRoot

        $savedEnv = @{}
        foreach ($name in 'DOTFILES_LOG_FILE', 'DOTFILES_LOG_LEVEL', 'CLAUDE_CONFIG_DIR') {
            $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        }

        # install.ps1 reads these when it is dot-sourced. Debug, so the log
        # shows the "already up to date" lines.
        $env:DOTFILES_LOG_FILE = Join-Path $testRoot 'dotfiles.log'
        $env:DOTFILES_LOG_LEVEL = 'debug'
        Remove-Item -Path Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

        # Dot-sourced, both define their functions without installing anything.
        . (Join-Path $repoRoot 'src/install.ps1')
        . (Join-Path $moduleRoot 'bootstrap.ps1')

        function ConvertTo-TestJson {
            param($Value)

            return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
        }

        # JSON text in the form ConvertTo-TestJson gives a merge result.
        function Get-ExpectedJson {
            param([string]$Text)

            return ConvertTo-TestJson -Value (ConvertFrom-ClaudeJson $Text)
        }

        function Invoke-TestMerge {
            param([string]$Current, [string]$Template)

            $merged = Merge-ClaudeJson -Current (ConvertFrom-ClaudeJson $Current) -Template (ConvertFrom-ClaudeJson $Template)
            return ConvertTo-TestJson -Value $merged
        }

        function New-TestDirectory {
            $path = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $path
            return $path
        }

        function Clear-TestLog {
            [IO.File]::WriteAllText($env:DOTFILES_LOG_FILE, '')
        }

        # The log since the last Clear-TestLog, one "<level>|<message>" per line.
        function Get-TestLog {
            if (-not (Test-Path -LiteralPath $env:DOTFILES_LOG_FILE)) {
                return
            }

            foreach ($line in [IO.File]::ReadAllLines($env:DOTFILES_LOG_FILE)) {
                if ($line.Trim().Length -gt 0) {
                    $entry = ConvertFrom-Json -InputObject $line
                    "$($entry.level)|$($entry.message)"
                }
            }
        }

        function Get-TestFileText {
            param([string]$Path)

            return [IO.File]::ReadAllText($Path)
        }

        function Get-TestFileHash {
            param([string]$Path)

            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        }

        # Every file under $Root as "<relative path>|<hash>|<write time>".
        function Get-TestTreeState {
            param([string]$Root)

            $rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\', '/')
            foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force | Sort-Object FullName)) {
                $relative = $file.FullName.Substring($rootPath.Length + 1)
                "$relative|$(Get-TestFileHash -Path $file.FullName)|$($file.LastWriteTimeUtc.Ticks)"
            }
        }

        # One record per hook in a settings object, in file order.
        function Get-TestHookRecord {
            param($Settings)

            $records = New-Object System.Collections.Generic.List[object]
            foreach ($hookEvent in $Settings.hooks.PSObject.Properties) {
                $entryIndex = 0
                foreach ($entry in $hookEvent.Value) {
                    $matcher = if ($entry.PSObject.Properties['matcher']) { $entry.matcher } else { '<none>' }
                    $hookIndex = 0
                    foreach ($hook in $entry.hooks) {
                        $records.Add([pscustomobject]@{
                                Event = $hookEvent.Name
                                Entry = $entryIndex
                                Matcher = $matcher
                                Index = $hookIndex
                                Hook = $hook
                            })
                        $hookIndex++
                    }
                    $entryIndex++
                }
            }

            return , $records.ToArray()
        }

        # The hook a POSIX template command runs: "<name>" or "<name> <mode>".
        function Get-TestPosixHookName {
            param([string]$Command)

            if ($Command -cnotmatch '^"\$\{CLAUDE_CONFIG_DIR:-\$HOME/\.claude\}"/hooks/(?<name>[A-Za-z0-9_]+)\.sh(?: (?<mode>[a-z-]+))?$') {
                throw "Unexpected POSIX hook command: $Command"
            }

            if ($Matches['mode']) {
                return "$($Matches['name']) $($Matches['mode'])"
            }
            return $Matches['name']
        }

        # Parses a Windows hook command, which must be & "<path>" [mode], and
        # evaluates its path in this session.
        function Get-TestWindowsHookTarget {
            param([string]$Command)

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Command, [ref]$tokens, [ref]$parseErrors)
            if (@($parseErrors).Count -gt 0) {
                throw "Hook command does not parse: $Command"
            }

            $statements = @($ast.EndBlock.Statements)
            if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) {
                throw "Hook command is not a single command: $Command"
            }

            $elements = @($statements[0].PipelineElements)
            if ($elements.Count -ne 1 -or $elements[0] -isnot [System.Management.Automation.Language.CommandAst] -or "$($elements[0].InvocationOperator)" -ne 'Ampersand') {
                throw "Hook command does not start with the call operator: $Command"
            }

            $commandElements = @($elements[0].CommandElements)
            $pathAst = $commandElements[0]
            if ($pathAst -isnot [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                throw "Hook path is not a double-quoted string: $Command"
            }

            $arguments = New-Object System.Collections.Generic.List[string]
            for ($i = 1; $i -lt $commandElements.Count; $i++) {
                if ($commandElements[$i] -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    throw "Hook argument is not a constant: $Command"
                }
                $arguments.Add($commandElements[$i].Value)
            }

            $path = & ([scriptblock]::Create($pathAst.Extent.Text))
            if ("$path" -cnotmatch '\\hooks\\(?<name>[A-Za-z0-9_]+)\.ps1$') {
                throw "Hook path is not hooks\<name>.ps1: $path"
            }
            $name = $Matches['name']

            return [pscustomobject]@{
                Path = "$path"
                Name = $name
                Hook = (@($name) + $arguments.ToArray()) -join ' '
            }
        }
    }

    AfterAll {
        foreach ($name in $savedEnv.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedEnv[$name])
        }
        if ($testRoot -and (Test-Path -LiteralPath $testRoot)) {
            foreach ($file in @(Get-ChildItem -LiteralPath $testRoot -Recurse -File -Force)) {
                if ($file.IsReadOnly) {
                    $file.IsReadOnly = $false
                }
            }
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Merge-ClaudeJson, row by row against CLAUDE_JSON_MERGE' {
        It 'objects in both: <Name>' -ForEach @(
            @{
                Name = 'merged key by key, recursively, keeping keys only in the existing file'
                Current = '{"a":{"x":1,"y":{"p":1}},"keep":true}'
                Template = '{"a":{"y":{"q":2},"z":3},"new":"n"}'
                Expected = '{"a":{"x":1,"y":{"p":1,"q":2},"z":3},"keep":true,"new":"n"}'
            }
            @{
                Name = 'existing keys keep their order and new keys are appended'
                Current = '{"b":1,"a":2}'
                Template = '{"c":3,"a":4}'
                Expected = '{"b":1,"a":4,"c":3}'
            }
            @{
                Name = 'an empty template object changes nothing'
                Current = '{"a":{"x":1}}'
                Template = '{"a":{}}'
                Expected = '{"a":{"x":1}}'
            }
        ) {
            Invoke-TestMerge -Current $Current -Template $Template | Should -BeExactly (Get-ExpectedJson -Text $Expected)
        }

        It 'arrays in both: <Name>' -ForEach @(
            @{
                Name = 'the existing items, then the template items not already there'
                Current = '{"a":[1,2]}'
                Template = '{"a":[2,3]}'
                Expected = '{"a":[1,2,3]}'
            }
            @{
                Name = 'duplicates already in the file stay'
                Current = '{"a":[1,1]}'
                Template = '{"a":[1]}'
                Expected = '{"a":[1,1]}'
            }
            @{
                Name = 'a new item the template repeats is added twice, as jq''s $b - $a does'
                Current = '{"a":[]}'
                Template = '{"a":[2,2]}'
                Expected = '{"a":[2,2]}'
            }
            @{
                Name = 'objects are equal whatever their key order'
                Current = '{"a":[{"x":1,"y":2}]}'
                Template = '{"a":[{"y":2,"x":1}]}'
                Expected = '{"a":[{"x":1,"y":2}]}'
            }
            @{
                Name = 'objects that differ in one field are both kept'
                Current = '{"a":[{"x":1,"y":2}]}'
                Template = '{"a":[{"x":1,"y":3}]}'
                Expected = '{"a":[{"x":1,"y":2},{"x":1,"y":3}]}'
            }
            @{
                Name = 'true is not 1'
                Current = '{"a":[1]}'
                Template = '{"a":[true]}'
                Expected = '{"a":[1,true]}'
            }
            @{
                Name = 'the string "1" is not the number 1'
                Current = '{"a":[1]}'
                Template = '{"a":["1"]}'
                Expected = '{"a":[1,"1"]}'
            }
            @{
                Name = 'false, 0, null and "" are all different'
                Current = '{"a":[0,""]}'
                Template = '{"a":[false,null,"",0]}'
                Expected = '{"a":[0,"",false,null]}'
            }
            @{
                Name = 'strings compare case-sensitively'
                Current = '{"a":["Read(*.env)"]}'
                Template = '{"a":["read(*.env)","Read(*.env)"]}'
                Expected = '{"a":["Read(*.env)","read(*.env)"]}'
            }
            @{
                Name = '1 and 1.0 are the same number'
                Current = '{"a":[1]}'
                Template = '{"a":[1.0]}'
                Expected = '{"a":[1]}'
            }
            @{
                Name = 'nested arrays compare item by item, in order'
                Current = '{"a":[[1,2]]}'
                Template = '{"a":[[1,2],[2,1]]}'
                Expected = '{"a":[[1,2],[2,1]]}'
            }
            @{
                Name = 'arrays inside objects inside arrays are not merged, only compared'
                Current = '{"a":[{"k":[1]}]}'
                Template = '{"a":[{"k":[1,2]}]}'
                Expected = '{"a":[{"k":[1]},{"k":[1,2]}]}'
            }
        ) {
            Invoke-TestMerge -Current $Current -Template $Template | Should -BeExactly (Get-ExpectedJson -Text $Expected)
        }

        It 'anything else, the template wins: <Name>' -ForEach @(
            @{
                Name = 'a string'
                Current = '{"model":"old"}'
                Template = '{"model":"new"}'
                Expected = '{"model":"new"}'
            }
            @{
                Name = 'a value of another type'
                Current = '{"a":{"x":1},"b":[1],"c":"s","d":1}'
                Template = '{"a":[1],"b":{"y":2},"c":5,"d":"1"}'
                Expected = '{"a":[1],"b":{"y":2},"c":5,"d":"1"}'
            }
            @{
                Name = 'null'
                Current = '{"a":1}'
                Template = '{"a":null}'
                Expected = '{"a":null}'
            }
            @{
                Name = 'false and the empty string'
                Current = '{"attribution":{"sessionUrl":true,"pr":"mine"}}'
                Template = '{"attribution":{"sessionUrl":false,"pr":""}}'
                Expected = '{"attribution":{"sessionUrl":false,"pr":""}}'
            }
        ) {
            Invoke-TestMerge -Current $Current -Template $Template | Should -BeExactly (Get-ExpectedJson -Text $Expected)
        }

        It 'a hook under an event in hooks: <Name>' -ForEach @(
            @{
                Name = 'an outdated copy of a template hook is replaced, not kept beside it'
                Current = '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":5}]}]}}'
                Template = '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":10}]}]}}'
                Expected = '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":10}]}]}}'
            }
            @{
                Name = 'only template commands are removed from an entry, which keeps its other keys and comes first'
                Current = '{"hooks":{"PreToolUse":[{"matcher":"Bash|Edit","hooks":[{"type":"command","command":"guard","timeout":5},{"type":"command","command":"mine"}],"x":1}]}}'
                Template = '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":10}]}]}}'
                Expected = '{"hooks":{"PreToolUse":[{"matcher":"Bash|Edit","hooks":[{"type":"command","command":"mine"}],"x":1},{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":10}]}]}}'
            }
            @{
                Name = 'entries left with no hooks are dropped, as is one that had none'
                Current = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]},{"hooks":[]},{"matcher":"m","hooks":[{"type":"command","command":"mine"}]}]}}'
                Template = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"a"}]},{"hooks":[{"type":"command","command":"b"}]}]}}'
                Expected = '{"hooks":{"Stop":[{"matcher":"m","hooks":[{"type":"command","command":"mine"}]},{"hooks":[{"type":"command","command":"a"}]},{"hooks":[{"type":"command","command":"b"}]}]}}'
            }
            @{
                Name = 'a template command only replaces hooks under the same event'
                Current = '{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"guard"}]}],"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}'
                Template = '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"guard"}]}]}}'
                Expected = '{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"guard"}]}],"Stop":[{"hooks":[{"type":"command","command":"mine"}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"guard"}]}]}}'
            }
            @{
                Name = 'commands compare exactly'
                Current = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"Guard"}]}]}}'
                Template = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"guard"}]}]}}'
                Expected = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"Guard"}]},{"hooks":[{"type":"command","command":"guard"}]}]}}'
            }
            @{
                Name = 'a file with no hooks gets the template''s'
                Current = '{"model":"m"}'
                Template = '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"guard"}]}]}}'
                Expected = '{"model":"m","hooks":{"Stop":[{"hooks":[{"type":"command","command":"guard"}]}]}}'
            }
            @{
                Name = 'merging the template into itself changes nothing'
                Current = '{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}'
                Template = '{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}'
                Expected = '{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}'
            }
        ) {
            Invoke-TestMerge -Current $Current -Template $Template | Should -BeExactly (Get-ExpectedJson -Text $Expected)
        }

        It 'bindings, merged by context: <Name>' -ForEach @(
            @{
                Name = 'a block with the same context gains the template keys, without a second block'
                Current = '{"bindings":[{"context":"Global","bindings":{"ctrl+k":"x"}},{"context":"Chat","bindings":{"enter":"chat:submit","ctrl+j":"chat:newline"}}]}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline","ctrl+enter":"chat:submit"}}]}'
                Expected = '{"bindings":[{"context":"Global","bindings":{"ctrl+k":"x"}},{"context":"Chat","bindings":{"enter":"chat:newline","ctrl+j":"chat:newline","ctrl+enter":"chat:submit"}}]}'
            }
            @{
                Name = 'a block for a new context is appended'
                Current = '{"bindings":[{"context":"Global","bindings":{"ctrl+k":"x"}}]}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"bindings":[{"context":"Global","bindings":{"ctrl+k":"x"}},{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            }
            @{
                Name = 'only the first of two blocks with the context is merged into'
                Current = '{"bindings":[{"context":"Chat","bindings":{"a":"1"}},{"context":"Chat","bindings":{"b":"2"}}]}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"bindings":[{"context":"Chat","bindings":{"a":"1","enter":"chat:newline"}},{"context":"Chat","bindings":{"b":"2"}}]}'
            }
            @{
                Name = 'contexts compare case-sensitively'
                Current = '{"bindings":[{"context":"chat","bindings":{"a":"1"}}]}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"bindings":[{"context":"chat","bindings":{"a":"1"}},{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            }
            @{
                Name = 'no bindings in the file'
                Current = '{"$docs":"d"}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"$docs":"d","bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            }
            @{
                Name = 'null bindings count as none'
                Current = '{"bindings":null}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            }
            @{
                Name = 'false bindings count as none, as jq''s // does'
                Current = '{"bindings":false}'
                Template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
                Expected = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            }
        ) {
            Invoke-TestMerge -Current $Current -Template $Template | Should -BeExactly (Get-ExpectedJson -Text $Expected)
        }

        It 'fails, as jq does, when bindings is <Name>' -ForEach @(
            @{ Name = 'a string'; Current = '{"bindings":"x"}' }
            @{ Name = 'an object'; Current = '{"bindings":{"context":"Chat"}}' }
        ) {
            $template = '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            { Invoke-TestMerge -Current $Current -Template $template } | Should -Throw
        }

        It 'never changes its inputs' {
            $currentText = '{"model":"old","permissions":{"allow":["a"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":5},{"type":"command","command":"mine"}]}]},"bindings":[{"context":"Chat","bindings":{"a":"1"}}]}'
            $templateText = '{"model":"new","permissions":{"allow":["b"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"guard","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"stop"}]}]},"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}},{"context":"Global","bindings":{"b":"2"}}]}'
            $current = ConvertFrom-ClaudeJson $currentText
            $template = ConvertFrom-ClaudeJson $templateText
            $currentBefore = ConvertTo-TestJson -Value $current
            $templateBefore = ConvertTo-TestJson -Value $template

            $null = Merge-ClaudeJson -Current $current -Template $template

            ConvertTo-TestJson -Value $current | Should -BeExactly $currentBefore
            ConvertTo-TestJson -Value $template | Should -BeExactly $templateBefore
        }

        It 'never changes its inputs when the file has no hooks or bindings' {
            $current = ConvertFrom-ClaudeJson '{"model":"old"}'
            $template = ConvertFrom-ClaudeJson '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"stop"}]}]},"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'
            $currentBefore = ConvertTo-TestJson -Value $current
            $templateBefore = ConvertTo-TestJson -Value $template

            $null = Merge-ClaudeJson -Current $current -Template $template

            ConvertTo-TestJson -Value $current | Should -BeExactly $currentBefore
            ConvertTo-TestJson -Value $template | Should -BeExactly $templateBefore
        }

        It 'keeps one-element and empty arrays as arrays through ConvertTo-ClaudeJson' {
            $current = ConvertFrom-ClaudeJson '{"one":[1],"empty":[],"nested":{"one":["x"]},"bindings":[]}'
            $template = ConvertFrom-ClaudeJson '{"newOne":["y"],"newEmpty":[],"deep":[[1]],"empty":[],"hooks":{"Stop":[{"hooks":[{"type":"command","command":"a"}]}]},"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'

            $text = ConvertTo-ClaudeJson (Merge-ClaudeJson -Current $current -Template $template)
            $parsed = ConvertFrom-ClaudeJson $text

            foreach ($case in @(
                    @{ Value = $parsed.one; Count = 1 }
                    @{ Value = $parsed.empty; Count = 0 }
                    @{ Value = $parsed.nested.one; Count = 1 }
                    @{ Value = $parsed.newOne; Count = 1 }
                    @{ Value = $parsed.newEmpty; Count = 0 }
                    @{ Value = $parsed.deep; Count = 1 }
                    @{ Value = $parsed.deep[0]; Count = 1 }
                    @{ Value = $parsed.hooks.Stop; Count = 1 }
                    @{ Value = $parsed.hooks.Stop[0].hooks; Count = 1 }
                    @{ Value = $parsed.bindings; Count = 1 }
                )) {
                ($case.Value -is [array]) | Should -BeTrue
                $case.Value.Count | Should -Be $case.Count
            }
        }

        It 'writes LF line endings and a final newline' {
            $text = ConvertTo-ClaudeJson (ConvertFrom-ClaudeJson '{"a":{"b":[1,2]}}')

            $text.Contains("`r") | Should -BeFalse
            $text.EndsWith("}`n") | Should -BeTrue
        }

        It 'merges the composed settings template into itself without a change' {
            $settings = Get-ClaudeSettingsTemplate -Templates $templatesDir -Windows $windowsDir

            ConvertTo-TestJson -Value (Merge-ClaudeJson -Current $settings -Template $settings) | Should -BeExactly (ConvertTo-TestJson -Value $settings)
        }
    }

    Context 'Merge-ClaudeJsonFile' {
        BeforeEach {
            $dir = New-TestDirectory
            $dest = Join-Path $dir 'settings.json'
            $source = Join-Path $dir 'template.json'
            $templateText = '{"model":"new","permissions":{"allow":["t"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"tpl","timeout":10}]}]}}'
            $template = ConvertFrom-ClaudeJson $templateText
            Clear-TestLog
        }

        AfterEach {
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                $info = New-Object System.IO.FileInfo -ArgumentList $dest
                if ($info.IsReadOnly) {
                    $info.IsReadOnly = $false
                }
            }
        }

        It 'creates a missing file from the template' {
            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            Get-TestFileText -Path $dest | Should -BeExactly (ConvertTo-ClaudeJson $template)
            Get-TestLog | Should -Contain "info|Claude Code configuration created at <$dest>."
        }

        It 'creates a missing parent directory' {
            $nested = Join-Path $dir 'a/b/settings.json'

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $nested | Should -BeTrue

            Get-TestFileText -Path $nested | Should -BeExactly (ConvertTo-ClaudeJson $template)
        }

        It 'replaces an empty file with the template' {
            [IO.File]::WriteAllText($dest, '')

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            Get-TestFileText -Path $dest | Should -BeExactly (ConvertTo-ClaudeJson $template)
            Get-TestLog | Should -Contain "info|Claude Code configuration created at <$dest>."
        }

        It 'replaces a whitespace-only file with the template' {
            [IO.File]::WriteAllText($dest, " `n`t`r`n ")

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            Get-TestFileText -Path $dest | Should -BeExactly (ConvertTo-ClaudeJson $template)
            Get-TestLog | Should -Contain "info|Merged dotfiles configuration into <$dest>."
        }

        It 'merges the template into an existing file' {
            $currentText = '{"model":"mine","theme":"dark","permissions":{"allow":["mine"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"tpl","timeout":5},{"type":"command","command":"mine"}]}]}}'
            [IO.File]::WriteAllText($dest, $currentText)

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            $expected = '{"model":"new","theme":"dark","permissions":{"allow":["mine","t"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]},{"hooks":[{"type":"command","command":"tpl","timeout":10}]}]}}'
            Get-TestFileText -Path $dest | Should -BeExactly (ConvertTo-ClaudeJson (ConvertFrom-ClaudeJson $expected))
            Get-TestLog | Should -Contain "info|Merged dotfiles configuration into <$dest>."
        }

        It 'writes UTF-8 without a BOM, with LF line endings' {
            [IO.File]::WriteAllText($dest, '{"name":"caf' + [char]0x00E9 + '"}')

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            $bytes = [IO.File]::ReadAllBytes($dest)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
            $text = (New-Object System.Text.UTF8Encoding -ArgumentList $false, $true).GetString($bytes)
            $text.Contains("`r") | Should -BeFalse
            (ConvertFrom-ClaudeJson $text).name | Should -BeExactly ('caf' + [char]0x00E9)
        }

        It 'keeps date-like strings as they are' {
            [IO.File]::WriteAllText($dest, '{"since":"2024-01-02T03:04:05Z"}')

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            Get-TestFileText -Path $dest | Should -Match ([regex]::Escape('"2024-01-02T03:04:05Z"'))
        }

        It 'reports a second run as up to date and leaves the bytes alone' {
            [IO.File]::WriteAllText($dest, '{"model":"mine","permissions":{"allow":["mine"]}}')
            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue
            $before = Get-TestFileHash -Path $dest
            $written = (Get-Item -LiteralPath $dest).LastWriteTimeUtc
            Clear-TestLog

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeTrue

            Get-TestFileHash -Path $dest | Should -BeExactly $before
            (Get-Item -LiteralPath $dest).LastWriteTimeUtc | Should -Be $written
            Get-TestLog | Should -Contain "debug|<$dest> is already up to date."
        }

        It 'leaves <Name> unchanged and fails' -ForEach @(
            @{ Name = 'invalid JSON'; Text = '{"model": '; Reason = $null }
            @{ Name = 'a JSON array of objects'; Text = '[{"model":"old"},{"theme":"dark"}]'; Reason = 'not a single JSON object' }
            @{ Name = 'a JSON array holding one object'; Text = '[{"model":"old"}]'; Reason = 'not a single JSON object' }
            @{ Name = 'an empty JSON array'; Text = '[]'; Reason = 'not a single JSON object' }
            @{ Name = 'a JSON string'; Text = '"settings"'; Reason = 'not a single JSON object' }
            @{ Name = 'a JSON number'; Text = '42'; Reason = 'not a single JSON object' }
            @{ Name = 'JSON null'; Text = 'null'; Reason = 'not a single JSON object' }
            @{ Name = 'two JSON objects'; Text = '{"a":1} {"b":2}'; Reason = $null }
        ) {
            [IO.File]::WriteAllText($dest, $Text)
            $before = Get-TestFileHash -Path $dest

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeFalse

            Get-TestFileHash -Path $dest | Should -BeExactly $before
            $errors = @(Get-TestLog | Where-Object { $_.StartsWith("error|Failed to merge <$source> into <$dest>, which was left unchanged: ") })
            $errors | Should -HaveCount 1
            if ($Reason) {
                $errors[0] | Should -BeExactly "error|Failed to merge <$source> into <$dest>, which was left unchanged: $Reason"
            }
            @(Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -like 'settings.json.dotfiles.*' }) | Should -HaveCount 0
        }

        It 'leaves a file whose bindings are not an array unchanged and fails' {
            [IO.File]::WriteAllText($dest, '{"bindings":"x"}')
            $keybindings = ConvertFrom-ClaudeJson '{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}'

            Merge-ClaudeJsonFile -Template $keybindings -Source $source -Destination $dest | Should -BeFalse

            Get-TestFileText -Path $dest | Should -BeExactly '{"bindings":"x"}'
            @(Get-TestLog | Where-Object { $_.StartsWith('error|Failed to merge') }) | Should -HaveCount 1
        }

        It 'leaves a symbolic link alone and fails' {
            $target = Join-Path $dir 'target.json'
            [IO.File]::WriteAllText($target, '{"model":"mine"}')
            try {
                $null = New-Item -ItemType SymbolicLink -Path $dest -Target $target -ErrorAction Stop
            } catch {
                Set-ItResult -Skipped -Because "this account cannot create symbolic links: $($_.Exception.Message)"
                return
            }

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeFalse

            Get-TestFileText -Path $target | Should -BeExactly '{"model":"mine"}'
            (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'
            Get-TestLog | Should -Contain "warn|Existing file <$dest> is a symbolic link and will be left alone."
        }

        It 'leaves a read-only file alone and fails' {
            [IO.File]::WriteAllText($dest, '{"model":"mine"}')
            (New-Object System.IO.FileInfo -ArgumentList $dest).IsReadOnly = $true

            Merge-ClaudeJsonFile -Template $template -Source $source -Destination $dest | Should -BeFalse

            Get-TestFileText -Path $dest | Should -BeExactly '{"model":"mine"}'
            Get-TestLog | Should -Contain "warn|Existing file <$dest> is read-only and will be left alone."
        }

        It 'fails without a template' {
            Merge-ClaudeJsonFile -Template $null -Source $source -Destination $dest | Should -BeFalse

            Test-Path -LiteralPath $dest | Should -BeFalse
        }
    }

    Context 'Get-ClaudeSettingsTemplate' {
        BeforeAll {
            $composed = Get-ClaudeSettingsTemplate -Templates $templatesDir -Windows $windowsDir
            $posix = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $templatesDir 'settings.json'))
            $windows = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $windowsDir 'settings.json'))

            # Windows has no commit-signing guard or no-session-links hook: their
            # PowerShell ports took about a second a call. Their rules stay.
            # Every other POSIX hook has a twin.
            $omittedHooks = @('commit_signing_guard', 'no_session_links')
            $expectedEvents = [ordered]@{}
            foreach ($hookEvent in $posix.hooks.PSObject.Properties) {
                $entries = @(foreach ($entry in $hookEvent.Value) {
                        $kept = @($entry.hooks | Where-Object { $omittedHooks -cnotcontains ((Get-TestPosixHookName -Command $_.command) -split ' ')[0] })
                        if ($kept.Count -gt 0) {
                            $copy = [ordered]@{}
                            if ($entry.PSObject.Properties['matcher']) { $copy.matcher = $entry.matcher }
                            $copy.hooks = $kept
                            [pscustomobject]$copy
                        }
                    })
                if ($entries.Count -gt 0) {
                    $expectedEvents[$hookEvent.Name] = $entries
                }
            }
            $posixExpected = [pscustomobject]@{ hooks = [pscustomobject]$expectedEvents }

            $posixHooks = Get-TestHookRecord -Settings $posixExpected
            $windowsHooks = Get-TestHookRecord -Settings $windows
            $windowsHookDir = Join-Path $windowsDir 'hooks'
            # The hooks this module ships on Windows: the twins of templates/hooks/*.sh.
            $knownHooks = @('wow_marker')
        }

        It 'registers and ships none of the omitted hooks' {
            foreach ($name in $omittedHooks) {
                foreach ($record in $windowsHooks) {
                    ($record.Hook.command -like "*$name*") | Should -BeFalse -Because $record.Hook.command
                }
                Test-Path -LiteralPath (Join-Path $windowsHookDir "$name.ps1") | Should -BeFalse -Because $name
            }
        }

        It 'has the same keys, in the same order, as templates/settings.json' {
            (@($composed.PSObject.Properties.Name) -join ',') | Should -BeExactly (@($posix.PSObject.Properties.Name) -join ',')
        }

        It 'equals templates/settings.json except for the hooks' {
            foreach ($property in $posix.PSObject.Properties) {
                if ($property.Name -ceq 'hooks') {
                    continue
                }
                ConvertTo-TestJson -Value $composed.($property.Name) | Should -BeExactly (ConvertTo-TestJson -Value $property.Value) -Because $property.Name
            }
        }

        It 'takes its hooks from windows/settings.json' {
            ConvertTo-TestJson -Value $composed.hooks | Should -BeExactly (ConvertTo-TestJson -Value $windows.hooks)
        }

        It 'reads nothing but hooks from windows/settings.json' {
            (@($windows.PSObject.Properties.Name) -join ',') | Should -BeExactly 'hooks'
        }

        It 'has the POSIX template''s events, less the omitted ones, in the same order' {
            (@($windows.hooks.PSObject.Properties.Name) -join ',') | Should -BeExactly (@($posixExpected.hooks.PSObject.Properties.Name) -join ',')
        }

        It 'has the POSIX template''s entries, matchers, types and timeouts, less the omitted ones' {
            $windowsHooks | Should -HaveCount $posixHooks.Count
            for ($i = 0; $i -lt $posixHooks.Count; $i++) {
                $p = $posixHooks[$i]
                $w = $windowsHooks[$i]
                $because = "hook $i, under $($p.Event)"
                $w.Event | Should -BeExactly $p.Event -Because $because
                $w.Entry | Should -Be $p.Entry -Because $because
                $w.Matcher | Should -BeExactly $p.Matcher -Because $because
                $w.Index | Should -Be $p.Index -Because $because
                $w.Hook.type | Should -BeExactly $p.Hook.type -Because $because
                $w.Hook.timeout | Should -Be $p.Hook.timeout -Because $because
            }
        }

        It 'runs the PowerShell twin of each POSIX hook, with the same mode' {
            for ($i = 0; $i -lt $posixHooks.Count; $i++) {
                $target = Get-TestWindowsHookTarget -Command $windowsHooks[$i].Hook.command
                $target.Hook | Should -BeExactly (Get-TestPosixHookName -Command $posixHooks[$i].Hook.command) -Because "hook $i, under $($posixHooks[$i].Event)"
            }
        }

        It 'runs every Windows hook with "shell": "powershell"' {
            foreach ($record in $windowsHooks) {
                $record.Hook.type | Should -BeExactly 'command'
                $record.Hook.PSObject.Properties['shell'] | Should -Not -BeNullOrEmpty -Because $record.Hook.command
                $record.Hook.shell | Should -BeExactly 'powershell' -Because $record.Hook.command
            }
        }

        It 'names a hook that exists in windows/hooks, or one of the module''s hooks, in every command' {
            foreach ($record in $windowsHooks) {
                $name = (Get-TestWindowsHookTarget -Command $record.Hook.command).Name
                $exists = Test-Path -LiteralPath (Join-Path $windowsHookDir "$name.ps1") -PathType Leaf
                ($exists -or ($knownHooks -ccontains $name)) | Should -BeTrue -Because $record.Hook.command
            }
        }

        It 'runs every hook in windows/hooks from some command' {
            $named = @(foreach ($record in $windowsHooks) { (Get-TestWindowsHookTarget -Command $record.Hook.command).Name })
            foreach ($file in @(Get-ChildItem -LiteralPath $windowsHookDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
                $named | Should -Contain $file.BaseName
            }
        }

        It 'finds each hook in CLAUDE_CONFIG_DIR when it is set, else in ~/.claude' {
            $saved = $env:CLAUDE_CONFIG_DIR
            try {
                foreach ($record in $windowsHooks) {
                    $env:CLAUDE_CONFIG_DIR = 'C:\Some Dir\claude'
                    $target = Get-TestWindowsHookTarget -Command $record.Hook.command
                    $target.Path | Should -BeExactly "C:\Some Dir\claude\hooks\$($target.Name).ps1"

                    Remove-Item -Path Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
                    $target = Get-TestWindowsHookTarget -Command $record.Hook.command
                    $target.Path | Should -BeExactly "$HOME\.claude\hooks\$($target.Name).ps1"
                }
            } finally {
                $env:CLAUDE_CONFIG_DIR = $saved
            }
        }
    }

    Context 'Invoke-Bootstrap' {
        BeforeAll {
            # A space in the path, as in many Windows profiles.
            $configDir = Join-Path (New-TestDirectory) 'claude config'
            $env:CLAUDE_CONFIG_DIR = $configDir

            Clear-TestLog
            $firstResult = Invoke-Bootstrap
            $firstLog = @(Get-TestLog)
            $firstState = @(Get-TestTreeState -Root $configDir)

            Clear-TestLog
            $secondResult = Invoke-Bootstrap
            $secondLog = @(Get-TestLog)
            $secondState = @(Get-TestTreeState -Root $configDir)

            # Shared templates that windows/ doesn't replace with its own copy.
            $sharedTemplates = @(
                Get-ChildItem -LiteralPath $templatesDir -Recurse -File -Force | Where-Object {
                    $relative = $_.FullName.Substring($templatesDir.Length + 1)
                    $top = ($relative -split '[\\/]')[0]
                    $relative -ne 'settings.json' -and $relative -ne 'keybindings.json' -and $top -ne 'hooks' -and
                    $_.Extension -ne '.pyc' -and $relative -notmatch '(^|[\\/])__pycache__[\\/]' -and
                    -not (Test-Path -LiteralPath (Join-Path $windowsDir $relative) -PathType Leaf)
                }
            )
            # Files windows/ lays over the shared templates, hooks and JSON aside.
            $overlayFiles = @(
                Get-ChildItem -LiteralPath $windowsDir -Recurse -File -Force | Where-Object {
                    $relative = $_.FullName.Substring($windowsDir.Length + 1)
                    $relative -ne 'settings.json' -and ($relative -split '[\\/]')[0] -ne 'hooks'
                }
            )
            $windowsHookFiles = @(Get-ChildItem -LiteralPath (Join-Path $windowsDir 'hooks') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
        }

        AfterAll {
            Remove-Item -Path Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
        }

        It 'succeeds' {
            $firstResult | Should -BeOfType ([bool])
            $firstResult | Should -BeTrue
            @($firstLog | Where-Object { $_.StartsWith('error|') }) | Should -HaveCount 0
        }

        It 'creates the config directory''s subdirectories' {
            foreach ($subdir in 'agents', 'commands', 'skills', 'rules', 'output-styles', 'hooks') {
                Test-Path -LiteralPath (Join-Path $configDir $subdir) -PathType Container | Should -BeTrue -Because $subdir
            }
        }

        It 'installs the shared rules and skills as they are' {
            $sharedTemplates.Count | Should -BeGreaterThan 0
            @($sharedTemplates | Where-Object { $_.FullName -match '[\\/]rules[\\/]' }).Count | Should -BeGreaterThan 0
            @($sharedTemplates | Where-Object { $_.FullName -match '[\\/]skills[\\/]' }).Count | Should -BeGreaterThan 0
            foreach ($file in $sharedTemplates) {
                $relative = $file.FullName.Substring($templatesDir.Length + 1)
                $installed = Join-Path $configDir $relative
                Test-Path -LiteralPath $installed -PathType Leaf | Should -BeTrue -Because $relative
                Get-TestFileHash -Path $installed | Should -BeExactly (Get-TestFileHash -Path $file.FullName) -Because $relative
            }
        }

        It 'installs the Windows copies of files that windows/ replaces' {
            $overlayFiles.Count | Should -BeGreaterThan 0
            foreach ($file in $overlayFiles) {
                $relative = $file.FullName.Substring($windowsDir.Length + 1)
                $installed = Join-Path $configDir $relative
                Get-TestFileHash -Path $installed | Should -BeExactly (Get-TestFileHash -Path $file.FullName) -Because $relative
            }
        }

        It 'installs a commit-signing rule that names no guard hook' {
            $rule = Get-TestFileText -Path (Join-Path $configDir 'rules/commit-signing.md')
            $rule | Should -Match 'No hook enforces this'
            $rule | Should -Not -Match 'guard hook enforces'
        }

        It 'installs a no-session-links rule that names no hook' {
            $rule = Get-TestFileText -Path (Join-Path $configDir 'rules/no-session-links.md')
            $rule | Should -Match 'No hook checks for these links'
            $rule | Should -Not -Match 'hook denies'
        }

        It 'installs none of the sh and Python hooks' {
            foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $templatesDir 'hooks') -File -Force)) {
                Test-Path -LiteralPath (Join-Path $configDir "hooks/$($file.Name)") | Should -BeFalse -Because $file.Name
            }
            @(Get-ChildItem -LiteralPath (Join-Path $configDir 'hooks') -Recurse -File -Force | Where-Object { $_.Extension -ne '.ps1' }) | Should -HaveCount 0
        }

        It 'installs the PowerShell hooks, and only them, in hooks' {
            foreach ($file in $windowsHookFiles) {
                $installed = Join-Path $configDir "hooks/$($file.Name)"
                Test-Path -LiteralPath $installed -PathType Leaf | Should -BeTrue -Because $file.Name
                Get-TestFileHash -Path $installed | Should -BeExactly (Get-TestFileHash -Path $file.FullName) -Because $file.Name
            }
            $installedNames = @(Get-ChildItem -LiteralPath (Join-Path $configDir 'hooks') -File -Force | Sort-Object Name | ForEach-Object { $_.Name })
            ($installedNames -join ',') | Should -BeExactly (@($windowsHookFiles | Sort-Object Name | ForEach-Object { $_.Name }) -join ',')
        }

        It 'creates settings.json from the composed template' {
            $installed = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $configDir 'settings.json'))
            $expected = Get-ClaudeSettingsTemplate -Templates $templatesDir -Windows $windowsDir

            ConvertTo-TestJson -Value $installed | Should -BeExactly (ConvertTo-TestJson -Value $expected)
        }

        It 'creates keybindings.json from the template' {
            $installed = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $configDir 'keybindings.json'))
            $expected = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $templatesDir 'keybindings.json'))

            ConvertTo-TestJson -Value $installed | Should -BeExactly (ConvertTo-TestJson -Value $expected)
        }

        It 'installs nothing else at the top of the config directory' {
            $names = @(Get-ChildItem -LiteralPath $configDir -File -Force | Sort-Object Name | ForEach-Object { $_.Name })
            ($names -join ',') | Should -BeExactly 'keybindings.json,settings.json'
        }

        It 'succeeds again on a second run, changing nothing' {
            $secondResult | Should -BeOfType ([bool])
            $secondResult | Should -BeTrue
            ($secondState -join "`n") | Should -BeExactly ($firstState -join "`n")
        }

        It 'reports both JSON files as up to date on a second run' {
            $secondLog | Should -Contain "debug|<$(Join-Path $configDir 'settings.json')> is already up to date."
            $secondLog | Should -Contain "debug|<$(Join-Path $configDir 'keybindings.json')> is already up to date."
            @($secondLog | Where-Object { $_.StartsWith('error|') -or $_ -like '*will be overwritten*' }) | Should -HaveCount 0
        }

        It 'replaces an outdated Windows hook in an existing settings.json and keeps the user''s settings' {
            $otherDir = Join-Path (New-TestDirectory) 'claude'
            $null = New-Item -ItemType Directory -Path $otherDir
            $windows = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $windowsDir 'settings.json'))
            $windowsHook = $windows.hooks.PreToolUse[0].hooks[0].command
            $existing = [pscustomobject]@{
                model = 'mine'
                permissions = [pscustomobject]@{ allow = @('Bash(ls)') }
                hooks = [pscustomobject]@{
                    PreToolUse = @(
                        [pscustomobject]@{
                            matcher = 'Bash|Monitor|Edit|Write|MultiEdit|NotebookEdit'
                            hooks = @([pscustomobject]@{ type = 'command'; shell = 'powershell'; command = $windowsHook; timeout = 5 })
                        }
                        [pscustomobject]@{
                            matcher = 'Bash'
                            hooks = @([pscustomobject]@{ type = 'command'; command = 'my-hook' })
                        }
                    )
                }
            }
            [IO.File]::WriteAllText((Join-Path $otherDir 'settings.json'), (ConvertTo-ClaudeJson $existing))

            $env:CLAUDE_CONFIG_DIR = $otherDir
            try {
                Invoke-Bootstrap | Should -BeTrue
            } finally {
                $env:CLAUDE_CONFIG_DIR = $configDir
            }

            $merged = ConvertFrom-ClaudeJson (Get-TestFileText -Path (Join-Path $otherDir 'settings.json'))
            $template = Get-ClaudeSettingsTemplate -Templates $templatesDir -Windows $windowsDir
            $merged.model | Should -BeExactly $template.model
            $merged.permissions.allow | Should -Contain 'Bash(ls)'
            ConvertTo-TestJson -Value $merged.permissions.deny | Should -BeExactly (ConvertTo-TestJson -Value $template.permissions.deny)

            $preToolUse = @($merged.hooks.PreToolUse)
            $preToolUse[0].hooks[0].command | Should -BeExactly 'my-hook'
            $replaced = @(foreach ($entry in $preToolUse) { foreach ($hook in $entry.hooks) { if ($hook.command -ceq $windowsHook) { $hook } } })
            $replaced | Should -HaveCount 1
            $replaced[0].timeout | Should -Be 10
            ConvertTo-TestJson -Value @($preToolUse | Select-Object -Skip 1) | Should -BeExactly (ConvertTo-TestJson -Value @($template.hooks.PreToolUse))
        }
    }
}
