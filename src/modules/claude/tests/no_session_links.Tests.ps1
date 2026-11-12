<#
Pester 5 tests for the Windows no-session-links hook,
windows/hooks/no_session_links.ps1: the cases of test_no_session_links.py,
plus Windows paths, Python's JSON output and runs of the hook in pwsh and
Windows PowerShell. Run with Invoke-Pester from the repository root.

Made-up links are built from parts so this file holds none: the hook, once
installed, would block writing it otherwise.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeDiscovery and BeforeAll variables with the blocks and It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'The target profiles know only the Pester 3 that ships with Windows; these tests need Pester 5.')]
param()

BeforeDiscovery {
    $linkHost = 'claude' + '.ai'
    $sessionId = 'session_' + '0123456789abcdefABCDEFxyz'
    $sessionUrl = "https://$linkHost/code/$sessionId"
    $trailer = 'Claude' + '-Session: ' + $sessionUrl
    $artifactUrls = @("https://$linkHost/artifact/abc123", "https://$linkHost/code/artifact/0f9e8d7c")
    $robot = [char]::ConvertFromUtf32(0x1F916)
    $onWindows = $env:OS -eq 'Windows_NT'

    $bashCases = @(
        @{ Expected = 'deny'; Command = "gh pr create --title x --body 'See $sessionUrl'" }
        @{ Expected = 'deny'; Command = "git commit -m x -m '$trailer'" }
        @{ Expected = 'deny'; Command = "git commit -F - <<'EOF'`nfeat: x`n`n  $trailer`nEOF" }
        @{ Expected = 'deny'; Command = "gh pr comment 1 --body $($artifactUrls[0])" }
        @{ Expected = 'deny'; Command = "gh issue create --body $($artifactUrls[1])" }
        @{ Expected = 'deny'; Command = "echo $sessionId >> notes.md" }
        @{ Expected = 'deny'; Command = "Claude-Session: $sessionUrl" }
        @{ Expected = 'allow'; Command = "git commit -m 'feat: x' -m 'Co-Authored-By: Claude <noreply@anthropic.com>'" }
        @{ Expected = 'allow'; Command = "gh pr create --body '$robot Generated with [Claude Code](https://claude.com/claude-code)'" }
        @{ Expected = 'allow'; Command = "curl -fsSL https://$linkHost/install.sh | bash" }
        @{ Expected = 'allow'; Command = "grep -nE 'claude\.ai|Claude-Session' msg.txt" }
        @{ Expected = 'allow'; Command = "echo 'drop claude.ai/code/session_... links'" }
        @{ Expected = 'allow'; Command = "git commit -m 'Mention Claude-Session: in prose'" }
        @{ Expected = 'allow'; Command = 'export SESSION_ID=session_short' }
    )

    $messageFileTemplates = @(
        @{ Template = 'git commit -F {path}' }
        @{ Template = 'git commit --file={path}' }
        @{ Template = 'git -C {dir} commit -F {name}' }
        @{ Template = 'git tag -a v1 -F {path}' }
        @{ Template = 'gh pr create --title x --body-file {path}' }
        @{ Template = 'gh pr edit 2 --body-file={path}' }
        @{ Template = 'gh release create v1 --notes-file {path}' }
    )

    $toolCases = @(
        @{ Expected = 'deny'; Tool = 'Write'; ToolInput = @{ file_path = '/r/README.md'; content = "Built in $sessionUrl`n" } }
        @{ Expected = 'deny'; Tool = 'Edit'; ToolInput = @{ file_path = '/r/a.md'; old_string = 'x'; new_string = $artifactUrls[0] } }
        @{ Expected = 'allow'; Tool = 'Edit'; ToolInput = @{ file_path = '/r/a.md'; old_string = $sessionUrl; new_string = 'x' } }
        @{ Expected = 'deny'; Tool = 'MultiEdit'; ToolInput = @{ file_path = '/r/a.md'; edits = @(@{ new_string = 'a' }, @{ new_string = $trailer }) } }
        @{ Expected = 'allow'; Tool = 'MultiEdit'; ToolInput = @{ file_path = '/r/a.md'; edits = 'not a list' } }
        @{ Expected = 'deny'; Tool = 'NotebookEdit'; ToolInput = @{ notebook_path = '/r/a.ipynb'; new_source = "# $sessionId" } }
        @{ Expected = 'deny'; Tool = 'mcp__github__create_pull_request'; ToolInput = @{ title = 'x'; body = @{ text = $sessionUrl } } }
        @{ Expected = 'allow'; Tool = 'mcp__github__create_pull_request'; ToolInput = @{ title = 'x'; body = 'Generated with Claude Code' } }
        @{ Expected = 'allow'; Tool = 'Read'; ToolInput = @{ file_path = $sessionUrl } }
        @{ Expected = 'allow'; Tool = 'Write'; ToolInput = @{ file_path = '/r/a.md'; content = 'See the README.' } }
        # Tool names are case-sensitive, as in the reference.
        @{ Expected = 'allow'; Tool = 'bash'; ToolInput = @{ command = "echo $sessionUrl" } }
        @{ Expected = 'allow'; Tool = 'MCP__github__create_issue'; ToolInput = @{ body = $sessionUrl } }
    )

    $otherInputs = @(
        @{ Name = 'empty'; Raw = '' }
        @{ Name = 'not JSON'; Raw = 'not json' }
        @{ Name = 'an array'; Raw = '[]' }
        @{ Name = 'a string tool_input'; Raw = '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": "' + $sessionUrl + '"}' }
        @{ Name = 'PostToolUse'; Raw = '{"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": "' + $sessionUrl + '"}}' }
        @{ Name = 'a BOM'; Raw = [string][char]0xFEFF + '{"tool_name": "Bash", "tool_input": {"command": "' + $sessionUrl + '"}}' }
        @{ Name = 'trailing data'; Raw = '{"tool_name": "Bash", "tool_input": {"command": "' + $sessionUrl + '"}} x' }
    )

    $shells = @(@{ Shell = 'pwsh' }, @{ Shell = 'powershell' })
}

BeforeAll {
    . "$PSScriptRoot/../windows/hooks/no_session_links.ps1"

    $HookPath = [System.IO.Path]::GetFullPath("$PSScriptRoot/../windows/hooks/no_session_links.ps1")
    $LinkHost = 'claude' + '.ai'
    $SessionId = 'session_' + '0123456789abcdefABCDEFxyz'
    $SessionUrl = "https://$LinkHost/code/$SessionId"
    $Trailer = 'Claude' + '-Session: ' + $SessionUrl
    $Footer = 'Co-Authored-By: Claude <noreply@anthropic.com>'
    $OnWindows = $env:OS -eq 'Windows_NT'

    function New-TestDirectory {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $path
        return $path
    }

    # A path as it would be typed in Git Bash: forward slashes.
    function ConvertTo-ShellPath {
        param([string]$Path)

        return $Path.Replace('\', '/')
    }

    # C:\Users\u\x as Git Bash writes it: /c/Users/u/x.
    function ConvertTo-MsysPath {
        param([string]$Path)

        return '/' + $Path.Substring(0, 1).ToLowerInvariant() + $Path.Substring(2).Replace('\', '/')
    }

    function Set-TextFile {
        param([string]$Path, [string]$Text)

        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    # The hook's entry point on an event's text, the way Claude Code passes
    # it, and its decision: allow (no output) or the permissionDecision.
    function Get-Decision {
        param([string]$Raw)

        $reply = Invoke-NoSessionLinksHook -InputText $Raw
        if ($reply -ceq '') {
            return 'allow'
        }
        return (ConvertFrom-Json -InputObject $reply).hookSpecificOutput.permissionDecision
    }

    function Invoke-PreToolUse {
        param([string]$Tool, $ToolInput, [string]$Cwd = $TestDrive)

        $payload = [ordered]@{
            hook_event_name = 'PreToolUse'
            tool_name = $Tool
            tool_input = $ToolInput
            cwd = $Cwd
        }
        return Get-Decision -Raw (ConvertTo-Json -InputObject $payload -Depth 20 -Compress)
    }

    function Invoke-Bash {
        param([string]$Command, [string]$Cwd = $TestDrive)

        return Invoke-PreToolUse -Tool 'Bash' -ToolInput @{ command = $Command } -Cwd $Cwd
    }

    # Runs a program with $InputBytes on stdin and returns its exit code,
    # stdout bytes and stderr text.
    function Invoke-TestProcess {
        param(
            [string]$FilePath,
            [string[]]$ArgumentList,
            [byte[]]$InputBytes = [byte[]]@(),
            [hashtable]$Environment = @{}
        )

        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $FilePath
        $info.Arguments = ConvertTo-ProcessArgumentString -Argument $ArgumentList
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($name in $Environment.Keys) {
            $info.EnvironmentVariables[$name] = $Environment[$name]
        }
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            $stdout = [System.IO.MemoryStream]::new()
            $stderr = [System.IO.MemoryStream]::new()
            $readOut = $process.StandardOutput.BaseStream.CopyToAsync($stdout)
            $readErr = $process.StandardError.BaseStream.CopyToAsync($stderr)
            $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(60000)) {
                $process.Kill()
                throw "$FilePath timed out"
            }
            $readOut.Wait()
            $readErr.Wait()
            return @{
                ExitCode = $process.ExitCode
                Stdout = $stdout.ToArray()
                Stderr = [System.Text.Encoding]::UTF8.GetString($stderr.ToArray())
            }
        } finally {
            $process.Dispose()
        }
    }

    function Invoke-TestGit {
        param([string]$Repo, [string[]]$ArgumentList)

        $git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $globalConfig = Join-Path $TestDrive 'empty.gitconfig'
        if (-not (Test-Path -LiteralPath $globalConfig)) {
            Set-TextFile -Path $globalConfig -Text ''
        }
        $environment = @{ HOME = $Repo; GIT_CONFIG_NOSYSTEM = '1'; GIT_CONFIG_GLOBAL = $globalConfig }
        $result = Invoke-TestProcess -FilePath $git -ArgumentList (@('-C', $Repo) + $ArgumentList) -Environment $environment
        if ($result.ExitCode -ne 0) {
            throw "git $ArgumentList failed: $($result.Stderr)"
        }
    }

    function New-TestCommit {
        param([string]$Repo, [string]$Message)

        Invoke-TestGit -Repo $Repo -ArgumentList @('-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '--allow-empty', '-m', $Message)
    }

    $ExpectedTail = -join @(
        ' The user never wants Claude Code session links, Claude-Session trailers or claude.ai ',
        'links in commits, pull requests, comments, issues, releases or files, even when Claude ',
        'Code''s attribution guidance asks for them. Remove the link and try again. Keep the ',
        'Co-Authored-By footer. Don''t work around this hook.'
    )

    # The reply the reference prints for $Problem, byte for byte.
    function Get-ExpectedReply {
        param([string]$Problem)

        $reason = 'Blocked by the no-session-links hook. ' + $Problem + '.' + $ExpectedTail
        return '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "' + $reason + '"}}'
    }
}

Describe 'no_session_links.ps1' {
    Context 'Bash commands' {
        It '<Expected>s <Command>' -ForEach $bashCases {
            Invoke-Bash -Command $Command | Should -BeExactly $Expected
        }

        It 'checks Monitor commands' {
            Invoke-PreToolUse -Tool 'Monitor' -ToolInput @{ command = "echo $SessionUrl" } | Should -BeExactly 'deny'
        }
    }

    Context 'message files' {
        It 'reads the file in <Template>' -ForEach $messageFileTemplates {
            $message = Join-Path (Join-Path (New-TestDirectory) 'sub') 'msg.txt'
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $message)
            $command = $Template.Replace('{path}', (ConvertTo-ShellPath -Path $message))
            $command = $command.Replace('{dir}', (ConvertTo-ShellPath -Path (Split-Path -Parent $message)))
            $command = $command.Replace('{name}', 'msg.txt')
            Set-TextFile -Path $message -Text "feat: x`n`n$Footer`n"
            Invoke-Bash -Command $command | Should -BeExactly 'allow'
            Set-TextFile -Path $message -Text "feat: x`n`n$Trailer`n"
            Invoke-Bash -Command $command | Should -BeExactly 'deny'
        }

        It 'resolves a relative message file against cwd' {
            $cwd = New-TestDirectory
            Set-TextFile -Path (Join-Path $cwd 'body.md') -Text "Summary`n`n$SessionUrl`n"
            Invoke-Bash -Command 'gh pr create --body-file body.md' -Cwd $cwd | Should -BeExactly 'deny'
        }

        It 'reads files only for git and gh' {
            $cwd = New-TestDirectory
            Set-TextFile -Path (Join-Path $cwd 'body.md') -Text "$SessionUrl`n"
            Invoke-Bash -Command 'sort -F body.md' -Cwd $cwd | Should -BeExactly 'allow'
            Invoke-Bash -Command 'gh api repos/o/r/issues -F title=x -F body=@body.md' -Cwd $cwd | Should -BeExactly 'allow'
            # Words are case-sensitive: GIT isn't git.
            Invoke-Bash -Command 'GIT commit -F body.md' -Cwd $cwd | Should -BeExactly 'allow'
        }

        It 'skips a file over 1,000,000 bytes' {
            $cwd = New-TestDirectory
            Set-TextFile -Path (Join-Path $cwd 'big.md') -Text ("$SessionUrl`n" + ('x' * 1000000))
            Invoke-Bash -Command 'git commit -F big.md' -Cwd $cwd | Should -BeExactly 'allow'
        }

        It 'reads a CRLF file and names the line' {
            $cwd = New-TestDirectory
            Set-TextFile -Path (Join-Path $cwd 'msg.txt') -Text "feat: x`r`n`r`n  $Trailer  `r`n"
            $reply = Invoke-NoSessionLinksHook -InputText (ConvertTo-Json -Compress -InputObject ([ordered]@{
                        hook_event_name = 'PreToolUse'
                        tool_name = 'Bash'
                        tool_input = @{ command = 'git commit -F msg.txt' }
                        cwd = $cwd
                    }))
            $reply | Should -BeExactly (Get-ExpectedReply -Problem "A message file passed to the command contains a Claude Code session URL: $Trailer")
        }

        It 'expands ~ to HOME' {
            $userHome = New-TestDirectory
            Set-TextFile -Path (Join-Path $userHome 'msg.txt') -Text "$Trailer`n"
            $saved = $env:HOME
            try {
                $env:HOME = $userHome
                Invoke-Bash -Command 'git commit -F ~/msg.txt' | Should -BeExactly 'deny'
            } finally {
                $env:HOME = $saved
            }
        }
    }

    Context 'Windows paths' -Skip:(-not $onWindows) {
        BeforeAll {
            $Dir = New-TestDirectory
            $Message = Join-Path $Dir 'msg.txt'
            Set-TextFile -Path $Message -Text "feat: x`n`n$Trailer`n"
        }

        It 'reads a Git Bash /c/ path' {
            Invoke-Bash -Command ('git commit -F ' + (ConvertTo-MsysPath -Path $Message)) | Should -BeExactly 'deny'
        }

        It 'reads a quoted backslash path' {
            Invoke-Bash -Command "git commit -F '$Message'" | Should -BeExactly 'deny'
        }

        It 'reads a file under git -C with a Git Bash path' {
            Invoke-Bash -Command ('git -C ' + (ConvertTo-MsysPath -Path $Dir) + ' commit -F msg.txt') | Should -BeExactly 'deny'
        }

        It 'reads /tmp as the user''s temp directory' {
            $saved = $env:TEMP
            try {
                $env:TEMP = $Dir
                Invoke-Bash -Command 'git commit -F /tmp/msg.txt' | Should -BeExactly 'deny'
            } finally {
                $env:TEMP = $saved
            }
        }

        It 'falls back to USERPROFILE without HOME' {
            $savedHome = $env:HOME
            $savedProfile = $env:USERPROFILE
            try {
                $env:HOME = $null
                $env:USERPROFILE = $Dir
                Invoke-Bash -Command 'git commit -F ~\\msg.txt' | Should -BeExactly 'deny'
            } finally {
                $env:HOME = $savedHome
                $env:USERPROFILE = $savedProfile
            }
        }

        It 'skips a device name' {
            Invoke-Bash -Command 'git commit -F NUL' | Should -BeExactly 'allow'
        }
    }

    Context 'git push' {
        It 'checks the commits no remote has' {
            if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }
            $repo = Join-Path (New-TestDirectory) 'repo'
            Invoke-TestGit -Repo $TestDrive -ArgumentList @('init', '-q', $repo)
            $shellRepo = ConvertTo-ShellPath -Path $repo
            New-TestCommit -Repo $repo -Message 'feat: clean'
            Invoke-Bash -Command "git -C $shellRepo push" | Should -BeExactly 'allow'
            New-TestCommit -Repo $repo -Message "feat: x`n`n$Trailer"
            Invoke-Bash -Command "git -C $shellRepo push -u origin HEAD" | Should -BeExactly 'deny'
            if ($OnWindows) {
                Invoke-Bash -Command ('git -C ' + (ConvertTo-MsysPath -Path $repo) + ' push') | Should -BeExactly 'deny'
            }
            # Once a remote has it, rewording is the user's call, not the hook's.
            Invoke-TestGit -Repo $repo -ArgumentList @('update-ref', 'refs/remotes/origin/main', 'HEAD')
            Invoke-Bash -Command "git -C $shellRepo push" | Should -BeExactly 'allow'
        }

        It 'names the commit in the reason' {
            if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }
            $repo = Join-Path (New-TestDirectory) 'repo'
            Invoke-TestGit -Repo $TestDrive -ArgumentList @('init', '-q', $repo)
            New-TestCommit -Repo $repo -Message "feat: x`n`n$Trailer"
            $problem = Get-BashProblem -Command 'git push' -Cwd $repo
            $problem | Should -Match '^Unpushed commit [0-9a-f]+ has a Claude Code session URL in its message: Claude-Session: '
            $problem | Should -Match 'Reword it before you push$'
        }

        It 'decides nothing outside a repository' {
            Invoke-Bash -Command 'git push' -Cwd (New-TestDirectory) | Should -BeExactly 'allow'
        }
    }

    Context 'other tools' {
        It '<Expected>s <Tool>' -ForEach $toolCases {
            Invoke-PreToolUse -Tool $Tool -ToolInput $ToolInput | Should -BeExactly $Expected
        }
    }

    Context 'the reply' {
        It 'names the link in the deny reason' {
            $raw = ConvertTo-Json -Compress -InputObject ([ordered]@{
                    hook_event_name = 'PreToolUse'
                    tool_name = 'Bash'
                    tool_input = @{ command = "git commit -m '$Trailer'" }
                })
            $reason = (ConvertFrom-Json -InputObject (Invoke-NoSessionLinksHook -InputText $raw)).hookSpecificOutput.permissionDecisionReason
            $reason | Should -BeLike '*a Claude Code session URL*'
            $reason | Should -BeLike '*Co-Authored-By*'
        }

        It 'is the reference''s JSON, byte for byte' {
            $raw = '{"hook_event_name": "PreToolUse", "tool_name": "Write", "tool_input": {"content": "x\n  caf\u00e9 \"' + $SessionUrl + '\"\t\n"}}'
            $expected = Get-ExpectedReply -Problem ('The text being written contains a Claude Code session URL: caf\u00e9 \"' + $SessionUrl + '\"')
            Invoke-NoSessionLinksHook -InputText $raw | Should -BeExactly $expected
        }

        It 'quotes an MCP input as Python''s json.dumps writes it' {
            $raw = '{"tool_name": "mcp__x__y", "tool_input": {"n": 1.0, "e": 1E16, "s": 0.00001, "z": -0, "b": [true, null], "u": "\u00e9", "url": "' + $SessionUrl + '"}}'
            $line = '{"n": 1.0, "e": 1e+16, "s": 1e-05, "z": 0, "b": [true, null], "u": "' + [char]0xE9 + '", "url": "' + $SessionUrl + '"}'
            # Python quotes the first 120 characters of the one-line dump.
            $line = $line.Substring(0, 120).Replace('"', '\"').Replace([string][char]0xE9, '\u00e9')
            Invoke-NoSessionLinksHook -InputText $raw | Should -BeExactly (Get-ExpectedReply -Problem ('The tool input contains a Claude Code session URL: ' + $line))
        }

        It 'cuts the line to 120 code points' {
            $face = [char]::ConvertFromUtf32(0x1F600)
            $text = ($face * 130) + ' ' + $SessionUrl
            $raw = '{"tool_name": "Write", "tool_input": {"content": "' + $text + '"}}'
            $escaped = '\ud83d\ude00' * 120
            Invoke-NoSessionLinksHook -InputText $raw | Should -BeExactly (Get-ExpectedReply -Problem ('The text being written contains a Claude Code session URL: ' + $escaped))
        }

        It 'decides nothing for <Name> input' -ForEach $otherInputs {
            Invoke-NoSessionLinksHook -InputText $Raw | Should -BeExactly ''
        }
    }

    Context 'JSON numbers' {
        # What Python's json.dumps(json.loads(text)) prints. Windows
        # PowerShell's own Double.Parse and ToString get some of these wrong.
        It 'writes <Text> back as <Expected>' -ForEach @(
            @{ Text = '8.5225050989308184944e+05'; Expected = '852250.5098930818' }
            @{ Text = '-88706234648137544631320576.0'; Expected = '-8.870623464813754e+25' }
            @{ Text = '-6.666125502206515e-212'; Expected = '-6.666125502206515e-212' }
            @{ Text = '1.7976931348623157e308'; Expected = '1.7976931348623157e+308' }
            @{ Text = '1.7976931348623158e308'; Expected = '1.7976931348623157e+308' }
            @{ Text = '2e308'; Expected = 'Infinity' }
            @{ Text = '4.9e-324'; Expected = '5e-324' }
            @{ Text = '-0.0'; Expected = '-0.0' }
            @{ Text = '-1e-400'; Expected = '-0.0' }
            @{ Text = '0.1'; Expected = '0.1' }
            @{ Text = '0.30000000000000004'; Expected = '0.30000000000000004' }
            @{ Text = '1E16'; Expected = '1e+16' }
            @{ Text = '1e15'; Expected = '1000000000000000.0' }
            @{ Text = '0.0001'; Expected = '0.0001' }
            @{ Text = '0.00001'; Expected = '1e-05' }
            @{ Text = '123.456e2'; Expected = '12345.6' }
            @{ Text = '-0'; Expected = '0' }
            @{ Text = '123'; Expected = '123' }
        ) {
            $isFloat = $Text.IndexOfAny([char[]]@('.', 'e', 'E')) -ge 0
            Format-JsonNumber -Text $Text -IsFloat $isFloat | Should -BeExactly $Expected
        }
    }

    Context 'command words' {
        It 'splits like shlex: <Command>' -ForEach @(
            @{ Command = 'git commit -m "a b" -F x'; Words = @('git', 'commit', '-m', 'a b', '-F', 'x') }
            @{ Command = 'a''b c''d "e\"f\\g\h" i\ j'; Words = @('ab cd', 'e"f\g\h', 'i j') }
            @{ Command = 'x "" '''' y'; Words = @('x', '', '', 'y') }
            @{ Command = "a`tb`r`nc"; Words = @('a', 'b', 'c') }
            @{ Command = 'git commit -m "unclosed'; Words = @('git', 'commit', '-m', '"unclosed') }
            @{ Command = 'trailing \'; Words = @('trailing', '\') }
        ) {
            $actual = Split-CommandWord -Command $Command
            $actual.Count | Should -Be $Words.Count
            for ($i = 0; $i -lt $Words.Count; $i++) {
                $actual[$i] | Should -BeExactly $Words[$i]
            }
        }
    }

    Context 'run as Claude Code runs it, in <Shell>' -ForEach $shells {
        BeforeAll {
            $Exe = Get-Command $Shell -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            $Arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', "& '$HookPath'")
            $Utf8 = [System.Text.UTF8Encoding]::new($false)
        }

        It 'prints the deny reply as UTF-8 without a BOM' {
            if (-not $Exe) {
                Set-ItResult -Skipped -Because "$Shell is not installed"
                return
            }
            $command = 'echo "caf' + [char]0xE9 + ' ' + $SessionUrl + '"'
            $hookEvent = '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": ' + (ConvertTo-JsonStringLiteral -Text $command) + '}}'
            $result = Invoke-TestProcess -FilePath $Exe.Source -ArgumentList $Arguments -InputBytes $Utf8.GetBytes($hookEvent)
            $expected = Get-ExpectedReply -Problem ('The command contains a Claude Code session URL: echo \"caf\u00e9 ' + $SessionUrl + '\"')
            $Utf8.GetString($result.Stdout) | Should -BeExactly $expected
            $result.Stdout[0] | Should -Not -Be 0xEF
            $result.Stderr | Should -BeExactly ''
            $result.ExitCode | Should -Be 0
        }

        It 'prints nothing for <Name>' -ForEach @(
            @{ Name = 'an allowed call'; Bytes = [System.Text.Encoding]::UTF8.GetBytes('{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "ls"}}') }
            @{ Name = 'broken JSON'; Bytes = [System.Text.Encoding]::UTF8.GetBytes('{"tool_name": ') }
            @{ Name = 'invalid UTF-8'; Bytes = [byte[]]@(0x7B, 0xFF, 0x7D) }
            @{ Name = 'no input'; Bytes = [byte[]]@() }
        ) {
            if (-not $Exe) {
                Set-ItResult -Skipped -Because "$Shell is not installed"
                return
            }
            $result = Invoke-TestProcess -FilePath $Exe.Source -ArgumentList $Arguments -InputBytes $Bytes
            $result.Stdout.Length | Should -Be 0
            $result.Stderr | Should -BeExactly ''
            $result.ExitCode | Should -Be 0
        }
    }
}
