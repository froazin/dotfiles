<#
Pester 5 tests for the ways-of-working marker hook's PowerShell twin
(windows/hooks/wow_marker.ps1), ported from test_wow_marker.py.

Most tests dot-source the hook and call Invoke-WowMarker, with a throwaway
HOME, WORKSPACE_DIR and XDG_RUNTIME_DIR under TestDrive. The end-to-end tests
pipe JSON into the hook with the PowerShell running the tests, as Claude Code
would: CI runs the suite under pwsh and under Windows PowerShell 5.1, so each
is covered once, in-process and spawned.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'The target profiles know only the Pester 3 that ships with Windows; these tests need Pester 5.')]
param()

BeforeDiscovery {
    $script:Shells = @(@{
            Shell = $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' })
            Exe = (Get-Process -Id $PID).Path
        })
}

BeforeAll {
    $script:Hook = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../windows/hooks/wow_marker.ps1'))
    $script:WindowsDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../windows'))
    . $script:Hook

    $script:OnWindows = $env:OS -eq 'Windows_NT'
    $script:Sep = [string][IO.Path]::DirectorySeparatorChar
    $script:Deny = "Ways of working is off: no directory touched in this session has a .wow marker, so wow-* skills don't apply."
    $script:Outside = 'Ways of working: off (outside <workspaces>).'
    $script:EnvNames = @('HOME', 'WORKSPACE_DIR', 'XDG_RUNTIME_DIR', 'XDG_CACHE_HOME', 'SUDO_HOME', 'TMP', 'TEMP', 'TMPDIR', 'CLAUDE_CONFIG_DIR')
    $script:SavedEnv = @{}

    function Get-OnLine {
        param([string]$Relative)

        $shown = '<workspaces>'
        if ($Relative) {
            $shown = '<workspaces>/' + $Relative
        }
        return "Ways of working: on for $shown (marker $shown/.wow)."
    }

    function Get-OffLine {
        param([string]$Relative)

        return "Ways of working: off for <workspaces>/$Relative (no .wow marker at or above it)."
    }

    function ConvertTo-NativePath {
        param([string]$Path)

        return $Path.Replace('/', $script:Sep)
    }

    # A throwaway home, workspace root and runtime directory, set in the
    # environment the hook reads.
    function New-Fixture {
        $tmp = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $fixture = @{
            Tmp = $tmp
            Home = Join-Path $tmp 'home'
            Ws = Join-Path $tmp 'workspaces'
            Run = Join-Path $tmp 'run'
        }
        $fixture.State = Join-Path $fixture.Run 'claude-wow'
        foreach ($dir in $fixture.Home, $fixture.Ws, $fixture.Run) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
        $env:HOME = $fixture.Home
        $env:WORKSPACE_DIR = $fixture.Ws
        $env:XDG_RUNTIME_DIR = $fixture.Run
        foreach ($name in 'XDG_CACHE_HOME', 'SUDO_HOME', 'CLAUDE_CONFIG_DIR') {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
        return $fixture
    }

    function New-WsDir {
        param([hashtable]$Fixture, [string]$Relative, [switch]$Marker)

        $path = $Fixture.Ws
        if ($Relative) {
            $path = Join-Path $Fixture.Ws (ConvertTo-NativePath -Path $Relative)
        }
        $null = New-Item -ItemType Directory -Path $path -Force
        if ($Marker) {
            [IO.File]::WriteAllText((Join-Path $path '.wow'), '')
        }
        return $path
    }

    function Get-StateName {
        param([hashtable]$Fixture)

        return @(Get-ChildItem -LiteralPath $Fixture.State -Force | ForEach-Object { $_.Name } | Sort-Object)
    }

    function Assert-NoLeak {
        param([hashtable]$Fixture, [hashtable]$Result)

        # Context never holds an absolute path, and JSON replies always parse.
        $text = $Result.Out + $Result.Err
        $text.IndexOf($Fixture.Tmp, [StringComparison]::OrdinalIgnoreCase) | Should -Be -1
        $text | Should -Not -Match '[A-Za-z]:[\\/]'
        if ($Result.Out.StartsWith('{')) {
            $null = ConvertFrom-Json -InputObject $Result.Out
        }
    }

    function ConvertTo-Byte {
        param([object]$Payload)

        if ($null -eq $Payload) {
            return , [byte[]]@()
        }
        if ($Payload -is [byte[]]) {
            return , $Payload
        }
        $text = $Payload
        if ($Payload -isnot [string]) {
            $text = ConvertTo-Json -InputObject $Payload -Depth 6 -Compress
        }
        return , ([Text.UTF8Encoding]::new($false)).GetBytes($text)
    }

    function Invoke-Hook {
        param([hashtable]$Fixture, [string]$Mode, [string]$Cwd, [object]$Payload, [string]$Argument)

        $result = Invoke-WowMarker -Mode $Mode -Argument $Argument -InputBytes (ConvertTo-Byte -Payload $Payload) -Directory $Cwd
        Assert-NoLeak -Fixture $Fixture -Result $result
        return $result
    }

    function Get-HookStatus {
        param([hashtable]$Fixture, [string]$Cwd, [string]$Argument)

        $result = Invoke-Hook -Fixture $Fixture -Mode 'status' -Cwd $Cwd -Argument $Argument
        return '{0}|{1}' -f $result.Code, $result.Out.Trim()
    }

    # The additionalContext of a JSON reply, or '' when there's none.
    function Get-HookContext {
        param([hashtable]$Result, [string]$EventName)

        if (-not $Result.Out) {
            return ''
        }
        $reply = ConvertFrom-Json -InputObject $Result.Out
        $reply.hookSpecificOutput.hookEventName | Should -BeExactly $EventName
        return [string]$reply.hookSpecificOutput.additionalContext
    }

    function Invoke-Pre {
        param([hashtable]$Fixture, [string]$Cwd, [string]$Tool, [hashtable]$ToolInput, [string]$Session = 's1', [string]$Agent)

        $payload = @{ session_id = $Session; hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = $ToolInput; cwd = $Cwd }
        if ($Agent) {
            $payload.agent_id = $Agent
        }
        $result = Invoke-Hook -Fixture $Fixture -Mode 'pre-tool' -Cwd $Cwd -Payload $payload
        $result.Code | Should -Be 0
        $result.Err | Should -BeExactly ''
        $result.Out | Should -Not -Match 'permissionDecision'
        return Get-HookContext -Result $result -EventName 'PreToolUse'
    }

    function Invoke-Read {
        param([hashtable]$Fixture, [string]$Cwd, [string]$Target, [string]$Session = 's1', [string]$Agent)

        $file = Join-Path $Target 'file.txt'
        return Invoke-Pre -Fixture $Fixture -Cwd $Cwd -Tool 'Read' -ToolInput @{ file_path = $file } -Session $Session -Agent $Agent
    }

    function Invoke-SessionStart {
        param([hashtable]$Fixture, [string]$Cwd, [string]$Session = 's1')

        return Invoke-Hook -Fixture $Fixture -Mode 'session-start' -Cwd $Cwd -Payload @{ session_id = $Session; source = 'startup' }
    }

    function Invoke-Skill {
        param([hashtable]$Fixture, [string]$Cwd, [string]$Name, [string]$Session = 's1')

        $payload = @{ session_id = $Session; tool_name = 'Skill'; tool_input = @{ skill = $Name } }
        $result = Invoke-Hook -Fixture $Fixture -Mode 'pre-skill' -Cwd $Cwd -Payload $payload
        return '{0}|{1}|{2}' -f $result.Code, $result.Out, $result.Err.Trim()
    }

    # A path in Git Bash form: /c/Users/... on Windows, unchanged elsewhere.
    function ConvertTo-BashPath {
        param([string]$Path)

        if (-not $script:OnWindows) {
            return $Path
        }
        return '/' + $Path.Substring(0, 1).ToLowerInvariant() + $Path.Substring(2).Replace('\', '/')
    }

    function New-Link {
        param([string]$Path, [string]$Target)

        $null = New-Item -ItemType SymbolicLink -Path $Path -Value $Target -ErrorAction Stop
    }

    function ConvertTo-Argument {
        param([string]$Value)

        if ($Value -and $Value -notmatch '[\s"]') {
            return $Value
        }
        $builder = [Text.StringBuilder]::new('"')
        $slashes = 0
        foreach ($c in $Value.ToCharArray()) {
            if ($c -eq '\') {
                $slashes++
                continue
            }
            if ($c -eq '"') {
                $null = $builder.Append('\', 2 * $slashes + 1).Append('"')
            } else {
                $null = $builder.Append('\', $slashes).Append($c)
            }
            $slashes = 0
        }
        $null = $builder.Append('\', 2 * $slashes).Append('"')
        return $builder.ToString()
    }

    # Runs a shell the way Claude Code does, with the event JSON on stdin.
    function Invoke-HookProcess {
        param([string]$Exe, [string[]]$Arguments, [string]$Cwd, [object]$Payload, [hashtable]$Environment = @{})

        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $Exe
        $info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-Argument -Value $_ })) -join ' '
        $info.WorkingDirectory = $Cwd
        $info.UseShellExecute = $false
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($name in $Environment.Keys) {
            if ($null -eq $Environment[$name]) {
                $info.EnvironmentVariables.Remove($name)
            } else {
                $info.EnvironmentVariables[$name] = $Environment[$name]
            }
        }
        $process = [Diagnostics.Process]::Start($info)
        $out = [IO.MemoryStream]::new()
        $err = [IO.MemoryStream]::new()
        $outTask = $process.StandardOutput.BaseStream.CopyToAsync($out)
        $errTask = $process.StandardError.BaseStream.CopyToAsync($err)
        $bytes = ConvertTo-Byte -Payload $Payload
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            throw "$Exe timed out"
        }
        $outTask.Wait()
        $errTask.Wait()
        $encoding = [Text.UTF8Encoding]::new($false)
        return @{
            Code = $process.ExitCode
            OutBytes = $out.ToArray()
            Out = $encoding.GetString($out.ToArray())
            Err = $encoding.GetString($err.ToArray())
        }
    }

    function Invoke-HookFile {
        param([string]$Exe, [string]$Mode, [string]$Cwd, [object]$Payload, [hashtable]$Environment = @{})

        $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:Hook, $Mode)
        return Invoke-HookProcess -Exe $Exe -Arguments $arguments -Cwd $Cwd -Payload $Payload -Environment $Environment
    }
}

# Pester 5 allows BeforeEach and AfterEach only inside a block.
Describe 'wow_marker.ps1' {
    BeforeEach {
        foreach ($name in $script:EnvNames) {
            $script:SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $script:Fx = New-Fixture
    }

    AfterEach {
        foreach ($name in $script:EnvNames) {
            [Environment]::SetEnvironmentVariable($name, $script:SavedEnv[$name])
        }
    }

    Describe 'status' {
        It 'reports on, off and outside' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r/src/deep') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/other') | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/other'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp | Should -BeExactly ('1|' + $script:Outside)
            Get-HookStatus -Fixture $fx -Cwd $fx.Home | Should -BeExactly ('1|' + $script:Outside)
        }

        It 'takes a directory argument' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument $repo | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Ws -Argument 'github.com/o/r' | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Ws -Argument (ConvertTo-NativePath 'github.com/o/r/../r') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
        }

        It 'reads Git Bash paths and compares case-insensitively' -Skip:($env:OS -ne 'Windows_NT') {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/Repo' -Marker
            $expected = '0|' + (Get-OnLine 'github.com/o/Repo')
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument $repo.Replace('\', '/') | Should -BeExactly $expected
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument (ConvertTo-BashPath $repo) | Should -BeExactly $expected
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument $repo.ToUpperInvariant() | Should -BeExactly $expected
            Get-HookStatus -Fixture $fx -Cwd $repo.ToLowerInvariant() | Should -BeExactly $expected
            $env:WORKSPACE_DIR = $fx.Ws.ToUpperInvariant()
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly $expected
            $env:WORKSPACE_DIR = ConvertTo-BashPath $fx.Ws
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly $expected
        }

        It 'defaults the root to the home directory''s workspaces' {
            $fx = $script:Fx
            Remove-Item -Path Env:WORKSPACE_DIR
            $repo = Join-Path $fx.Home (ConvertTo-NativePath 'workspaces/github.com/o/r')
            $null = New-Item -ItemType Directory -Path $repo -Force
            [IO.File]::WriteAllText((Join-Path $repo '.wow'), '')
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            if ($script:OnWindows) {
                Get-HookStatus -Fixture $fx -Cwd $fx.Tmp -Argument '~/workspaces/github.com/o/r' | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            }
            $env:SUDO_HOME = $fx.Tmp
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly ('1|' + $script:Outside)
        }

        It 'finds a marker at the root' {
            $fx = $script:Fx
            $null = New-WsDir -Fixture $fx -Relative '' -Marker
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r') | Should -BeExactly ('0|' + (Get-OnLine ''))
            Get-HookStatus -Fixture $fx -Cwd $fx.Ws | Should -BeExactly ('0|' + (Get-OnLine ''))
        }

        It 'lets the nearest marker win' {
            $fx = $script:Fx
            $null = New-WsDir -Fixture $fx -Relative 'github.com/o/mono' -Marker
            $null = New-WsDir -Fixture $fx -Relative 'github.com/o/mono/packages/a' -Marker
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/mono/packages/a/src') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/mono/packages/a'))
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/mono/packages/b') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/mono'))
        }

        It 'ignores a marker above the root' {
            $fx = $script:Fx
            [IO.File]::WriteAllText((Join-Path $fx.Tmp '.wow'), '')
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r') | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp | Should -BeExactly ('1|' + $script:Outside)
        }

        It 'does not count a .wow directory' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r'
            $null = New-Item -ItemType Directory -Path (Join-Path $repo '.wow')
            Get-HookStatus -Fixture $fx -Cwd $repo | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/r'))
        }

        It 'follows a .wow link the way sh''s -f does' {
            $fx = $script:Fx
            $file = Join-Path $fx.Tmp 'marker-file'
            [IO.File]::WriteAllText($file, '')
            $toFile = New-WsDir -Fixture $fx -Relative 'github.com/o/to-file'
            $dangling = New-WsDir -Fixture $fx -Relative 'github.com/o/dangling'
            $toDir = New-WsDir -Fixture $fx -Relative 'github.com/o/to-dir'
            $chain = New-WsDir -Fixture $fx -Relative 'github.com/o/chain'
            try {
                New-Link -Path (Join-Path $toFile '.wow') -Target $file
            } catch {
                Set-ItResult -Skipped -Because 'this account cannot create symbolic links'
                return
            }
            # Windows PowerShell's New-Item won't link to a missing target, so
            # link to a file and then delete it.
            $gone = Join-Path $fx.Tmp 'no-such-file'
            [IO.File]::WriteAllText($gone, '')
            New-Link -Path (Join-Path $dangling '.wow') -Target $gone
            [IO.File]::Delete($gone)
            New-Link -Path (Join-Path $toDir '.wow') -Target $fx.Home
            New-Link -Path (Join-Path $chain '.wow') -Target (Join-Path $toFile '.wow')
            Get-HookStatus -Fixture $fx -Cwd $toFile | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/to-file'))
            Get-HookStatus -Fixture $fx -Cwd $chain | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/chain'))
            Get-HookStatus -Fixture $fx -Cwd $dangling | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/dangling'))
            Get-HookStatus -Fixture $fx -Cwd $toDir | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/to-dir'))
            [IO.File]::Delete($file)
            Get-HookStatus -Fixture $fx -Cwd $chain | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/chain'))
        }

        It 'resolves a symbolic-linked root and links physically' {
            $fx = $script:Fx
            $real = Join-Path $fx.Tmp 'real-workspaces'
            $src = Join-Path $real (ConvertTo-NativePath 'github.com/o/r/src')
            $null = New-Item -ItemType Directory -Path $src -Force
            [IO.File]::WriteAllText((Join-Path $real (ConvertTo-NativePath 'github.com/o/r/.wow')), '')
            $link = Join-Path $fx.Tmp 'ws-link'
            try {
                New-Link -Path $link -Target $real
            } catch {
                Set-ItResult -Skipped -Because 'this account cannot create symbolic links'
                return
            }
            $env:WORKSPACE_DIR = $link
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $link (ConvertTo-NativePath 'github.com/o/r/src')) | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $src | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            # A link inside the root to somewhere outside it is outside.
            New-Link -Path (Join-Path $real 'escape') -Target $fx.Home
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $link 'escape') | Should -BeExactly ('1|' + $script:Outside)
            # A relative link, and a link to a link.
            Push-Location -LiteralPath (Join-Path $real 'github.com')
            try {
                $null = New-Item -ItemType SymbolicLink -Path 'rel' -Value (ConvertTo-NativePath 'o/r/src') -ErrorAction Stop
            } finally {
                Pop-Location
            }
            New-Link -Path (Join-Path $fx.Ws 'twice') -Target (Join-Path $real (ConvertTo-NativePath 'github.com/rel'))
            $env:WORKSPACE_DIR = $real
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $real (ConvertTo-NativePath 'github.com/rel')) | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $fx.Ws 'twice') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp -Argument (Join-Path $real (ConvertTo-NativePath 'github.com/rel/../..')) | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o'))
        }

        It 'resolves junctions physically' -Skip:($env:OS -ne 'Windows_NT') {
            $fx = $script:Fx
            $real = Join-Path $fx.Tmp 'real-workspaces'
            $null = New-Item -ItemType Directory -Path (Join-Path $real 'github.com\o\r\src') -Force
            [IO.File]::WriteAllText((Join-Path $real 'github.com\o\r\.wow'), '')
            $junction = Join-Path $fx.Tmp 'ws-junction'
            $null = New-Item -ItemType Junction -Path $junction -Value $real
            $env:WORKSPACE_DIR = $junction
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $junction 'github.com\o\r\src') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $real 'github.com\o\r\src') | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            $null = New-Item -ItemType Junction -Path (Join-Path $real 'escape') -Value $fx.Home
            Get-HookStatus -Fixture $fx -Cwd (Join-Path $junction 'escape') | Should -BeExactly ('1|' + $script:Outside)
            # A dangling junction counts as its parent.
            $gone = Join-Path $fx.Tmp 'gone'
            $null = New-Item -ItemType Directory -Path $gone
            $null = New-Item -ItemType Junction -Path (Join-Path $real 'github.com\o\dangling') -Value $gone
            [IO.Directory]::Delete($gone)
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp -Argument (Join-Path $real 'github.com\o\dangling') | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o'))
        }

        It 'treats a missing root as off' {
            $fx = $script:Fx
            $env:WORKSPACE_DIR = Join-Path $fx.Tmp 'missing'
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp | Should -BeExactly ('1|' + $script:Outside)
        }

        It 'treats a relative root as off' {
            $fx = $script:Fx
            $null = New-WsDir -Fixture $fx -Relative '' -Marker
            $env:WORKSPACE_DIR = 'workspaces'
            Get-HookStatus -Fixture $fx -Cwd $fx.Ws | Should -BeExactly ('1|' + $script:Outside)
            Get-HookStatus -Fixture $fx -Cwd $fx.Tmp -Argument 'workspaces' | Should -BeExactly ('1|' + $script:Outside)
        }

        It 'uses the nearest existing ancestor of a missing directory' {
            $fx = $script:Fx
            $null = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument (Join-Path $fx.Ws (ConvertTo-NativePath 'github.com/o/r/new/deeper')) | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument (Join-Path $fx.Ws (ConvertTo-NativePath 'github.com/o/new')) | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o'))
            # A file counts as its directory.
            [IO.File]::WriteAllText((Join-Path $fx.Ws (ConvertTo-NativePath 'github.com/o/r/f.txt')), '')
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument (Join-Path $fx.Ws (ConvertTo-NativePath 'github.com/o/r/f.txt')) | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
        }

        It 'leaves unsafe characters out of the line' {
            $fx = $script:Fx
            # Windows forbids " in a name, so use another character JSON or a
            # shell might treat specially.
            $odd = 'github.com/o/we ird"repo'
            if ($script:OnWindows) {
                $odd = 'github.com/o/we ird#repo'
            }
            $null = New-WsDir -Fixture $fx -Relative $odd -Marker
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative "$odd/src") | Should -BeExactly '0|Ways of working: on (marker found).'
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/sp ace') | Should -BeExactly '1|Ways of working: off (no .wow marker at or above this directory).'
            $accent = 'github.com/o/caf' + [char]0x00E9
            Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative $accent) | Should -BeExactly '1|Ways of working: off (no .wow marker at or above this directory).'
        }

        It 'lets a Git submodule inherit the marker' {
            $fx = $script:Fx
            # The walk never looks at .git: a submodule has a .git file, and its
            # parent a .git directory.
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/parent' -Marker
            $null = New-Item -ItemType Directory -Path (Join-Path $repo '.git')
            $sub = New-WsDir -Fixture $fx -Relative 'github.com/o/parent/sub/src'
            [IO.File]::WriteAllText((Join-Path $repo (ConvertTo-NativePath 'sub/.git')), "gitdir: ../.git/modules/sub`n")
            Get-HookStatus -Fixture $fx -Cwd $sub | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/parent'))
        }

        It 'never touches the state' {
            $fx = $script:Fx
            $null = Get-HookStatus -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker)
            Test-Path -LiteralPath $fx.State | Should -BeFalse
        }
    }

    Describe 'session-start and session-end' {
        It 'prints only when on' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $on = Invoke-SessionStart -Fixture $fx -Cwd $repo
            $on.Code | Should -Be 0
            $on.Out | Should -BeExactly ((Get-OnLine 'github.com/o/r') + "`n")
            $on.Err | Should -BeExactly ''
            $off = Invoke-SessionStart -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/other') -Session 's2'
            '{0}|{1}|{2}' -f $off.Code, $off.Out, $off.Err | Should -BeExactly '0||'
        }

        It 'resets the state' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Test-Path -LiteralPath (Join-Path $fx.State 's1.on') | Should -BeTrue
            (Invoke-SessionStart -Fixture $fx -Cwd $other).Out | Should -BeExactly ''
            Test-Path -LiteralPath (Join-Path $fx.State 's1.on') | Should -BeFalse
            [IO.File]::ReadAllText((Join-Path $fx.State 's1.state')) | Should -BeExactly "off`n"
            # After a reset (such as /clear or a compaction) a change is told again.
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/r')
        }

        It 'session-end removes only this session''s state' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $null = Invoke-SessionStart -Fixture $fx -Cwd $repo
            $null = Invoke-Read -Fixture $fx -Cwd $repo -Target $repo -Agent 'a1'
            [IO.File]::WriteAllText((Join-Path $fx.State 'other.state'), "off`n")
            [IO.File]::WriteAllText((Join-Path $fx.State 's10.state'), "off`n")
            $null = New-Item -ItemType Directory -Path (Join-Path $fx.State 's1.lock')
            (Get-StateName -Fixture $fx) -join ',' | Should -BeExactly 'other.state,s1.a1.state,s1.lock,s1.on,s1.state,s10.state'
            (Invoke-Hook -Fixture $fx -Mode 'session-end' -Cwd $repo -Payload @{ session_id = 's1' }).Code | Should -Be 0
            (Get-StateName -Fixture $fx) -join ',' | Should -BeExactly 'other.state,s10.state'
        }

        It 'keeps the state directory private' -Skip:($env:OS -eq 'Windows_NT') {
            $fx = $script:Fx
            $null = Invoke-SessionStart -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker)
            $item = Get-Item -LiteralPath $fx.State
            if (-not $item.PSObject.Properties['UnixMode'] -or -not [Type]::GetType('System.IO.UnixFileMode')) {
                Set-ItResult -Skipped -Because 'this PowerShell cannot set or read Unix modes'
                return
            }
            $item.UnixMode | Should -BeExactly 'drwx------'
        }

        It 'falls back to a per-user directory without XDG_RUNTIME_DIR' {
            $fx = $script:Fx
            Remove-Item -Path Env:XDG_RUNTIME_DIR
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            if ($script:OnWindows) {
                $temp = Join-Path $fx.Tmp 'temp'
                $null = New-Item -ItemType Directory -Path $temp
                $env:TMP = $temp
                $env:TEMP = $temp
                $state = Join-Path $temp 'claude-wow'
            } else {
                $state = Join-Path $fx.Home '.cache/claude-wow'
            }
            $null = Invoke-SessionStart -Fixture $fx -Cwd $repo
            [IO.File]::ReadAllText((Join-Path $state 's1.state')) | Should -BeExactly "on:github.com/o/r`n"
        }

        It 'falls back when XDG_RUNTIME_DIR is missing' {
            $fx = $script:Fx
            $env:XDG_RUNTIME_DIR = Join-Path $fx.Tmp 'no-such-dir'
            $env:XDG_CACHE_HOME = Join-Path $fx.Tmp 'cache'
            $temp = Join-Path $fx.Tmp 'temp'
            $null = New-Item -ItemType Directory -Path $temp
            $env:TMP = $temp
            $env:TEMP = $temp
            $null = Invoke-SessionStart -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker)
            Test-Path -LiteralPath $env:XDG_RUNTIME_DIR | Should -BeFalse
            $state = Join-Path $fx.Tmp (ConvertTo-NativePath 'cache/claude-wow')
            if ($script:OnWindows) {
                $state = Join-Path $temp 'claude-wow'
            }
            Test-Path -LiteralPath (Join-Path $state 's1.state') | Should -BeTrue
        }
    }

    Describe 'pre-tool and post-bash' {
        It 'announces <Tool> only on a change' -ForEach @(
            @{ Tool = 'Read'; ToolInput = @{ file_path = '{repo}/src/a.txt' }; Cwd = 'other' }
            @{ Tool = 'Edit'; ToolInput = @{ file_path = '{repo}/a.txt'; old_string = 'a'; new_string = 'b' }; Cwd = 'other' }
            @{ Tool = 'Write'; ToolInput = @{ file_path = '{repo}/new/dir/a.txt'; content = 'x' }; Cwd = 'other' }
            @{ Tool = 'MultiEdit'; ToolInput = @{ file_path = '{repo}/a.txt'; edits = @() }; Cwd = 'other' }
            @{ Tool = 'NotebookEdit'; ToolInput = @{ notebook_path = '{repo}/n.ipynb'; new_source = '' }; Cwd = 'other' }
            @{ Tool = 'Glob'; ToolInput = @{ pattern = '*.md'; path = '{repo}' }; Cwd = 'other' }
            @{ Tool = 'Glob'; ToolInput = @{ pattern = '*.md'; path = '../r/src' }; Cwd = 'other' }
            @{ Tool = 'Glob'; ToolInput = @{ pattern = '*.md' }; Cwd = 'repo' }
            @{ Tool = 'Grep'; ToolInput = @{ pattern = 'x'; path = '{repo}/src/a.txt' }; Cwd = 'other' }
            @{ Tool = 'Grep'; ToolInput = @{ pattern = 'x' }; Cwd = 'repo' }
            @{ Tool = 'Bash'; ToolInput = @{ command = 'ls' }; Cwd = 'repo' }
            @{ Tool = 'Monitor'; ToolInput = @{ command = 'tail -f log' }; Cwd = 'repo' }
            # Windows paths as Claude Code sends them, and the forms Git Bash uses.
            @{ Tool = 'Read'; ToolInput = @{ file_path = '{repo\}\src\a.txt' }; Cwd = 'other' }
            @{ Tool = 'Edit'; ToolInput = @{ file_path = '{repo/}/a.txt' }; Cwd = 'other' }
            @{ Tool = 'Glob'; ToolInput = @{ pattern = '*.md'; path = '{repo-bash}/src' }; Cwd = 'other' }
            @{ Tool = 'Grep'; ToolInput = @{ pattern = 'x'; path = '..\r\src' }; Cwd = 'other' }
        ) {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $null = New-WsDir -Fixture $fx -Relative 'github.com/o/r/src'
            [IO.File]::WriteAllText((Join-Path $repo (ConvertTo-NativePath 'src/a.txt')), '')
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $filled = @{}
            foreach ($key in $ToolInput.Keys) {
                $value = $ToolInput[$key]
                if ($value -is [string]) {
                    $value = $value.Replace('{repo\}', $repo).Replace('{repo/}', $repo.Replace('\', '/')).Replace('{repo-bash}', (ConvertTo-BashPath $repo)).Replace('{repo}', $repo)
                    if (-not $script:OnWindows) {
                        $value = $value.Replace('\', '/')
                    }
                }
                $filled[$key] = $value
            }
            $directory = $other
            if ($Cwd -eq 'repo') {
                $directory = $repo
            }
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            Invoke-Pre -Fixture $fx -Cwd $directory -Tool $Tool -ToolInput $filled | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Pre -Fixture $fx -Cwd $directory -Tool $Tool -ToolInput $filled | Should -BeExactly ''
        }

        It 'goes on, off and on again in a monorepo' {
            $fx = $script:Fx
            $mono = New-WsDir -Fixture $fx -Relative 'github.com/o/mono'
            $a = New-WsDir -Fixture $fx -Relative 'github.com/o/mono/a' -Marker
            $b = New-WsDir -Fixture $fx -Relative 'github.com/o/mono/b'
            $c = New-WsDir -Fixture $fx -Relative 'github.com/o/mono/c' -Marker
            (Invoke-SessionStart -Fixture $fx -Cwd $mono).Out | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $mono -Target $mono | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $mono -Target $a | Should -BeExactly (Get-OnLine 'github.com/o/mono/a')
            Invoke-Read -Fixture $fx -Cwd $mono -Target (Join-Path $a 'deeper') | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $mono -Target $b | Should -BeExactly (Get-OffLine 'github.com/o/mono/b')
            Invoke-Read -Fixture $fx -Cwd $mono -Target $mono | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $mono -Target $a | Should -BeExactly (Get-OnLine 'github.com/o/mono/a')
            Invoke-Read -Fixture $fx -Cwd $mono -Target $c | Should -BeExactly (Get-OnLine 'github.com/o/mono/c')
            Invoke-Read -Fixture $fx -Cwd $mono -Target $fx.Home | Should -BeExactly $script:Outside
        }

        It 'keeps a case change from announcing again' -Skip:($env:OS -ne 'Windows_NT') {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/Repo' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/Repo')
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo.ToLowerInvariant() | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo.ToUpperInvariant() | Should -BeExactly ''
        }

        It 'keeps subagent state separate' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            (Invoke-SessionStart -Fixture $fx -Cwd $repo).Out.Trim() | Should -BeExactly (Get-OnLine 'github.com/o/r')
            $started = Invoke-Hook -Fixture $fx -Mode 'subagent-start' -Cwd $other -Payload @{ session_id = 's1'; agent_id = 'a1'; agent_type = 'Explore' }
            '{0}|{1}' -f $started.Code, $started.Out | Should -BeExactly '0|'
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo -Agent 'a1' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo -Agent 'a1' | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $other -Target $other -Agent 'a2' | Should -BeExactly ''
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo -Agent 'a2' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            $on = Invoke-Hook -Fixture $fx -Mode 'subagent-start' -Cwd $repo -Payload @{ session_id = 's1'; agent_id = 'a3' }
            Get-HookContext -Result $on -EventName 'SubagentStart' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Read -Fixture $fx -Cwd $repo -Target $repo -Agent 'a3' | Should -BeExactly ''
        }

        It 'post-bash uses the current directory' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            $payload = @{
                session_id = 's1'
                tool_name = 'Bash'
                tool_input = @{ command = "cd $other" }
                tool_response = @{ stdout = "$other/x"; stderr = '' }
            }
            $results = foreach ($cwd in $repo, $repo, $other) {
                $result = Invoke-Hook -Fixture $fx -Mode 'post-bash' -Cwd $cwd -Payload $payload
                $result.Code | Should -Be 0
                Get-HookContext -Result $result -EventName 'PostToolUse'
            }
            $results[0] | Should -BeExactly (Get-OnLine 'github.com/o/r')
            $results[1] | Should -BeExactly ''
            $results[2] | Should -BeExactly (Get-OffLine 'github.com/o/other')
        }

        It 'still announces past a held lock <Kind>' -ForEach @(
            @{ Kind = 'directory' }
            @{ Kind = 'file' }
        ) {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            $lock = Join-Path $fx.State 's1.lock'
            if ($Kind -eq 'directory') {
                $null = New-Item -ItemType Directory -Path $lock
            } else {
                [IO.File]::WriteAllText($lock, '')
            }
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Test-Path -LiteralPath $lock | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $fx.State 's1.on') | Should -BeTrue
        }

        It 'goes stateless at once when the state directory is unwritable' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            if ($script:OnWindows) {
                $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                $null = & icacls.exe $fx.State /deny "${user}:(OI)(CI)(W,D,DC)"
            } else {
                $null = & chmod 0500 $fx.State
            }
            try {
                $probe = Join-Path $fx.State 'probe'
                try {
                    [IO.File]::WriteAllText($probe, '')
                    [IO.File]::Delete($probe)
                    Set-ItResult -Skipped -Because 'this account can write past the permissions'
                    return
                } catch {
                    $probe = $null
                }
                Lock-WowState -Path (Join-Path $fx.State 's1.lock') | Should -BeExactly 'Denied'
                # Like the sh hook without state: every on directory is told,
                # without waiting 20 times for a lock it can't take.
                $clock = [Diagnostics.Stopwatch]::StartNew()
                Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/r')
                Invoke-Read -Fixture $fx -Cwd $other -Target $repo | Should -BeExactly (Get-OnLine 'github.com/o/r')
                $clock.ElapsedMilliseconds | Should -BeLessThan 900
            } finally {
                if ($script:OnWindows) {
                    $null = & icacls.exe $fx.State /remove:d $user
                } else {
                    $null = & chmod 0700 $fx.State
                }
            }
        }

        It 'leaves no lock behind' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $null = Invoke-SessionStart -Fixture $fx -Cwd (New-WsDir -Fixture $fx -Relative 'github.com/o/other')
            $null = Invoke-Read -Fixture $fx -Cwd $repo -Target $repo
            (Get-StateName -Fixture $fx) -join ',' | Should -BeExactly 's1.on,s1.state'
            [IO.File]::ReadAllText((Join-Path $fx.State 's1.state')) | Should -BeExactly "on:github.com/o/r`n"
        }
    }

    Describe 'pre-skill and expand' {
        It 'gates wow-* skills' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            foreach ($name in 'wow-commits', 'plugin:wow-commits', '/wow-commits') {
                Invoke-Skill -Fixture $fx -Cwd $other -Name $name | Should -BeExactly ('2||' + $script:Deny)
            }
            foreach ($name in 'commit', 'my-wow-thing', 'plugin:other', 'WOW-commits') {
                Invoke-Skill -Fixture $fx -Cwd $other -Name $name | Should -BeExactly '0||'
            }
            # The current directory being on is enough.
            Invoke-Skill -Fixture $fx -Cwd $repo -Name 'wow-commits' | Should -BeExactly '0||'
            # So is any directory touched in this session, even after leaving it.
            $null = Invoke-Read -Fixture $fx -Cwd $other -Target $repo
            $null = Invoke-Read -Fixture $fx -Cwd $other -Target $other
            Invoke-Skill -Fixture $fx -Cwd $other -Name 'wow-commits' | Should -BeExactly '0||'
            Invoke-Skill -Fixture $fx -Cwd $other -Name 'plugin:wow-commits' | Should -BeExactly '0||'
            # A subagent shares the session's flag.
            $agent = Invoke-Hook -Fixture $fx -Mode 'pre-skill' -Cwd $other -Payload @{ session_id = 's1'; agent_id = 'a1'; tool_input = @{ skill = 'wow-commits' } }
            $agent.Code | Should -Be 0
        }

        It 'adds a note to a typed command when off' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            $expand = {
                param([string]$Cwd, [string]$Name)
                $result = Invoke-Hook -Fixture $fx -Mode 'expand' -Cwd $Cwd -Payload @{ session_id = 's1'; command_name = $Name; prompt = '/' + $Name }
                $result.Code | Should -Be 0
                $result
            }
            $note = Get-HookContext -Result (& $expand $other 'wow-commits') -EventName 'UserPromptExpansion'
            $note | Should -BeExactly 'Ways of working: off here (no .wow marker). The user typed /wow-commits explicitly.'
            $note = Get-HookContext -Result (& $expand $other '/plugin:wow-x') -EventName 'UserPromptExpansion'
            $note | Should -BeExactly 'Ways of working: off here (no .wow marker). The user typed /plugin:wow-x explicitly.'
            $note = Get-HookContext -Result (& $expand $other 'wow-"x y') -EventName 'UserPromptExpansion'
            $note | Should -BeExactly 'Ways of working: off here (no .wow marker). The user typed the command explicitly.'
            (& $expand $other 'review').Out | Should -BeExactly ''
            (& $expand $repo 'wow-commits').Out | Should -BeExactly ''
            $null = Invoke-Read -Fixture $fx -Cwd $other -Target $repo
            (& $expand $other 'wow-commits').Out | Should -BeExactly ''
        }
    }

    Describe 'Windows paths' -Skip:($env:OS -ne 'Windows_NT') {
        It 'treats <Path> as outside without contacting the host' -ForEach @(
            # 192.0.2.1 is TEST-NET-1: contacting it would stall about 21 s.
            @{ Path = '\\192.0.2.1\share\a.txt' }
            @{ Path = '//192.0.2.1/share/a.txt' }
            @{ Path = '\\?\UNC\192.0.2.1\share\a.txt' }
            @{ Path = '\\192.0.2.1\share' }
            @{ Path = '\\192.0.2.1' }
            @{ Path = '\\.\pipe\x\a.txt' }
        ) {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $null = Invoke-SessionStart -Fixture $fx -Cwd $repo
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Invoke-Pre -Fixture $fx -Cwd $repo -Tool 'Read' -ToolInput @{ file_path = $Path } | Should -BeExactly $script:Outside
            Get-HookStatus -Fixture $fx -Cwd $repo -Argument $Path | Should -BeExactly ('1|' + $script:Outside)
            $clock.ElapsedMilliseconds | Should -BeLessThan 5000
        }

        It 'treats a session directory on another share as outside' {
            $fx = $script:Fx
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Get-HookStatus -Fixture $fx -Cwd '\\192.0.2.1\share\x' | Should -BeExactly ('1|' + $script:Outside)
            Get-HookStatus -Fixture $fx -Cwd '\\192.0.2.1\share\x' -Argument 'y' | Should -BeExactly ('1|' + $script:Outside)
            $clock.ElapsedMilliseconds | Should -BeLessThan 5000
        }

        It 'reads a \\.\C: device path as the drive path' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument ('\\.\' + $repo) | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r'))
        }

        It 'never matches a name Windows forbids, such as <Name>' -ForEach @(
            @{ Name = 'r<' }
            @{ Name = 'r>>>' }
            @{ Name = '<<<' }
            @{ Name = 'r"' }
            @{ Name = 'r*' }
            @{ Name = '?' }
            @{ Name = 'r.' }
            @{ Name = 'r ' }
            @{ Name = 'r|' }
            @{ Name = 'r:x' }
        ) {
            $fx = $script:Fx
            $null = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $path = Join-Path $fx.Ws ('github.com\o\' + $Name + '\a.txt')
            Get-HookStatus -Fixture $fx -Cwd $fx.Home -Argument $path | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o'))
            Resolve-WowChild -Parent (Join-Path $fx.Ws 'github.com\o') -Name $Name -Depth 0 -Share '' | Should -BeNullOrEmpty
        }
    }

    Describe 'bad input' {
        It 'never errors or blocks in <Mode> on malformed input' -ForEach @(
            foreach ($mode in 'session-start', 'subagent-start', 'pre-tool', 'post-bash', 'pre-skill', 'expand', 'session-end') {
                foreach ($stdin in '', 'not json', '{', '{"session_id":', '{"session_id": 1, "tool_input": null}', '<NUL SOH>', '[]', '"s"', '{"tool_input": "wow-x", "skill": "wow-x"}', '{"session_id":"s1","tool_input":{"skill":["wow-x"]}}') {
                    @{ Mode = $mode; Stdin = $stdin }
                }
            }
        ) {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            # Kept out of the -ForEach data, which Pester writes into its XML report.
            $payload = if ($Stdin -ceq '<NUL SOH>') { "{0}{1}`n`n" -f [char]0, [char]1 } else { $Stdin }
            $result = Invoke-Hook -Fixture $fx -Mode $Mode -Cwd $repo -Payload $payload
            '{0}|{1}' -f $result.Code, $result.Err | Should -BeExactly '0|'
        }

        It 'treats odd session id "<Session>" as stateless' -ForEach @(
            @{ Session = '../escape' }
            @{ Session = 'a b' }
            @{ Session = 'a/b' }
            @{ Session = 'a\b' }
            @{ Session = 'a.b' }
            @{ Session = '' }
            @{ Session = '*' }
            @{ Session = "s1`n" }
        ) {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            (Invoke-SessionStart -Fixture $fx -Cwd $repo -Session $Session).Out.Trim() | Should -BeExactly (Get-OnLine 'github.com/o/r')
            # Without state, every on directory is told and off ones never are.
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo -Session $Session | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Read -Fixture $fx -Cwd $other -Target $repo -Session $Session | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Read -Fixture $fx -Cwd $repo -Target $other -Session $Session | Should -BeExactly ''
            (Invoke-Hook -Fixture $fx -Mode 'session-end' -Cwd $repo -Payload @{ session_id = $Session }).Code | Should -Be 0
            if (Test-Path -LiteralPath $fx.State) {
                @(Get-ChildItem -LiteralPath $fx.State -Force).Count | Should -Be 0
            }
            Test-Path -LiteralPath (Join-Path $fx.Tmp 'escape.state') | Should -BeFalse
        }

        It 'treats an odd agent id as stateless' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $null = Invoke-SessionStart -Fixture $fx -Cwd $repo
            Invoke-Read -Fixture $fx -Cwd $repo -Target $repo -Agent '../x' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            Invoke-Read -Fixture $fx -Cwd $repo -Target $repo -Agent '../x' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            (Get-StateName -Fixture $fx) -join ',' | Should -BeExactly 's1.on,s1.state'
        }

        It 'decodes values with JSON escapes, unlike the sh hook' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            # A Windows path always arrives with escaped backslashes.
            $escaped = $repo.Replace('\', '\\').Replace('/', '\/')
            $raw = '{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"' + $escaped + '\/a.txt"}}'
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $raw) -EventName 'PreToolUse' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            # A quote inside a value can't end it early or inject another key.
            $tricky = @{ session_id = 's1'; tool_input = @{ file_path = 'x" ,"file_path":"' + $repo + '/a' } }
            $result = Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $tricky
            '{0}|{1}|{2}' -f $result.Code, $result.Out, $result.Err | Should -BeExactly '0||'
            $command = @{ session_id = 's1'; tool_input = @{ command = "echo `"`n`"skill`":`"x`"`nfile_path=$repo/a" } }
            $result = Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $command
            '{0}|{1}|{2}' -f $result.Code, $result.Out, $result.Err | Should -BeExactly '0||'
            # A key at the wrong level doesn't count.
            $nested = @{ session_id = 's1'; tool_input = @{ command = 'ls' }; tool_response = @{ file_path = "$repo/a" } }
            $result = Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $nested
            $result.Out | Should -BeExactly ''
            # An escaped session id is the id it decodes to, and an escaped
            # separator is a separator (\ on Windows, / elsewhere).
            $separator = '\/'
            if ($script:OnWindows) {
                $separator = '\\'
            }
            $unicode = '{"session_id":"s\u0031","tool_input":{"file_path":"' + $escaped + $separator + 'a"}}'
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $unicode) -EventName 'PreToolUse' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            [IO.File]::ReadAllText((Join-Path $fx.State 's1.state')) | Should -BeExactly "on:github.com/o/r`n"
        }

        It 'reads nothing from input that is not one object' {
            $fx = $script:Fx
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            # pwsh would unroll a one-item array and 5.1 not, so neither reads it.
            $wrapped = '[{"session_id":"s1","tool_input":{"skill":"wow-commits"}}]'
            $result = Invoke-Hook -Fixture $fx -Mode 'pre-skill' -Cwd $other -Payload $wrapped
            '{0}|{1}|{2}' -f $result.Code, $result.Out, $result.Err | Should -BeExactly '0||'
            $fields = Read-WowInput -Bytes (ConvertTo-Byte -Payload $wrapped)
            $fields.SessionId + '|' + $fields.Skill | Should -BeExactly '|'
            $fields = Read-WowInput -Bytes (ConvertTo-Byte -Payload ("`r`n " + $wrapped.Substring(1, $wrapped.Length - 2)))
            $fields.SessionId + '|' + $fields.Skill | Should -BeExactly 's1|wow-commits'
        }

        It 'reads pretty-printed input' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            $payload = ConvertTo-Json -InputObject @{ session_id = 's1'; tool_name = 'Read'; tool_input = @{ file_path = "$repo/a" } } -Depth 4
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $payload) -EventName 'PreToolUse' | Should -BeExactly (Get-OnLine 'github.com/o/r')
        }

        It 'reads past invalid UTF-8 and a byte order mark' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            $encoding = [Text.UTF8Encoding]::new($false)
            $tail = $encoding.GetBytes('","file_path":"' + $repo.Replace('\', '\\') + '/a"}}')
            $raw = [byte[]]([byte[]](0xEF, 0xBB, 0xBF) + $encoding.GetBytes('{"session_id":"s1","tool_input":{"content":"bad') + [byte[]](0xFF) + $tail)
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $other -Payload $raw) -EventName 'PreToolUse' | Should -BeExactly (Get-OnLine 'github.com/o/r')
        }

        It 'tells a marker name with a newline once' -Skip:($env:OS -eq 'Windows_NT') {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative "github.com/o/new`nline" -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $other
            Invoke-Pre -Fixture $fx -Cwd $repo -Tool 'Bash' -ToolInput @{ command = 'true' } | Should -BeExactly 'Ways of working: on (marker found).'
            Invoke-Pre -Fixture $fx -Cwd $repo -Tool 'Bash' -ToolInput @{ command = 'true' } | Should -BeExactly ''
        }

        It 'resolves an absolute path when the session directory is gone' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $gone = New-WsDir -Fixture $fx -Relative 'github.com/o/gone'
            $null = Invoke-SessionStart -Fixture $fx -Cwd $gone
            [IO.Directory]::Delete($gone)
            $payload = @{ session_id = 's1'; tool_input = @{ file_path = "$repo/a" } }
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $gone -Payload $payload) -EventName 'PreToolUse' | Should -BeExactly (Get-OnLine 'github.com/o/r')
            # Relative paths can't resolve, so they count as outside.
            $relative = @{ session_id = 's1'; tool_input = @{ path = 'src' } }
            Get-HookContext -Result (Invoke-Hook -Fixture $fx -Mode 'pre-tool' -Cwd $gone -Payload $relative) -EventName 'PreToolUse' | Should -BeExactly $script:Outside
        }
    }

    Describe 'functions' {
        It 'converts <Path> to <Expected>' -Skip:($env:OS -ne 'Windows_NT') -ForEach @(
            @{ Path = '/c/Users/u/x'; Expected = 'C:\Users\u\x' }
            @{ Path = '/d'; Expected = 'D:\' }
            @{ Path = 'C:/Users/u/x'; Expected = 'C:\Users\u\x' }
            @{ Path = '\\?\C:\x'; Expected = 'C:\x' }
            @{ Path = '\??\C:\x'; Expected = 'C:\x' }
            @{ Path = '\\.\C:\x'; Expected = 'C:\x' }
            @{ Path = '//./c:/x'; Expected = 'c:\x' }
            @{ Path = '\\.\pipe\x'; Expected = '\\.\pipe\x' }
            @{ Path = '//host/share/x'; Expected = '\\host\share\x' }
            @{ Path = '\\?\UNC\server\share\x'; Expected = '\\server\share\x' }
            @{ Path = '/cd/x'; Expected = '\cd\x' }
            @{ Path = 'rel/x'; Expected = 'rel\x' }
        ) {
            ConvertTo-WowPath -Path $Path | Should -BeExactly $Expected
        }

        It 'expands ~ on Windows' -Skip:($env:OS -ne 'Windows_NT') {
            $env:HOME = 'C:\Users\jdoe'
            ConvertTo-WowPath -Path '~' | Should -BeExactly 'C:\Users\jdoe'
            ConvertTo-WowPath -Path '~/a/b' | Should -BeExactly 'C:\Users\jdoe\a\b'
            ConvertTo-WowPath -Path '~\a' | Should -BeExactly 'C:\Users\jdoe\a'
            ConvertTo-WowPath -Path '~jdoe/a' | Should -BeExactly '~jdoe\a'
            Remove-Item -Path Env:HOME
            $env:USERPROFILE | Should -Not -BeNullOrEmpty
            ConvertTo-WowPath -Path '~' | Should -BeExactly $env:USERPROFILE
        }

        It 'tells which UNC paths must not be opened' -Skip:($env:OS -ne 'Windows_NT') {
            Get-WowShare -Path '\\Host\Share\x\y' | Should -BeExactly '\\Host\Share'
            Get-WowShare -Path '\\host' | Should -BeExactly '\\host'
            Get-WowShare -Path 'C:\x' | Should -BeExactly ''
            Get-WowVolume -Path '\\host\share\x' | Should -BeExactly '\\host\share'
            Get-WowVolume -Path 'C:\x' | Should -BeExactly 'C:'
            Test-WowRemote -Path 'C:\x' -Share '' | Should -BeFalse
            Test-WowRemote -Path '\\host\share\x' -Share '' | Should -BeTrue
            Test-WowRemote -Path '\\host\share\x' -Share '\\HOST\Share' | Should -BeFalse
            Test-WowRemote -Path '\\host\other\x' -Share '\\host\share' | Should -BeTrue
            Test-WowRemote -Path '\\host\share\x' -Share '*' | Should -BeFalse
            foreach ($device in '\\.\pipe\x', '\\.', '\\?\Volume{0}\x') {
                Test-WowRemote -Path $device -Share '*' | Should -BeTrue
            }
            # Never opened: a share other than the root's comes back as it is.
            Resolve-WowPath -Path '\\192.0.2.1\share\x' -Partial -Share '' | Should -BeExactly '\\192.0.2.1\share\x'
            Resolve-WowPath -Path '\\.\pipe\x' -Partial -Share '' | Should -BeNullOrEmpty
        }

        It 'takes the lock, finds it held, or finds the state directory unwritable' {
            $dir = Join-Path $script:Fx.Tmp 'locks'
            $null = New-Item -ItemType Directory -Path $dir
            Lock-WowState -Path (Join-Path $dir 'a.lock') | Should -BeExactly 'Locked'
            Lock-WowState -Path (Join-Path $dir 'a.lock') | Should -BeExactly 'Held'
            $null = New-Item -ItemType Directory -Path (Join-Path $dir 'b.lock')
            Lock-WowState -Path (Join-Path $dir 'b.lock') | Should -BeExactly 'Held'
            Lock-WowState -Path (Join-Path $dir (ConvertTo-NativePath 'missing/c.lock')) | Should -BeExactly 'Held'
        }

        It 'finds the directory part of a file path' {
            Get-WowDirectoryName -Path 'a.txt' | Should -BeExactly '.'
            Get-WowDirectoryName -Path (ConvertTo-NativePath 'a/b.txt') | Should -BeExactly 'a'
            Get-WowDirectoryName -Path ($script:Sep + 'a.txt') | Should -BeExactly $script:Sep
            if ($script:OnWindows) {
                Get-WowDirectoryName -Path 'C:\a.txt' | Should -BeExactly 'C:\'
            }
        }

        It 'matches wow-* names' {
            foreach ($name in 'wow-a', '/wow-a', 'p:wow-a', '/p:wow-a', 'a:b:wow-') {
                Test-WowName -Name $name | Should -BeTrue
            }
            foreach ($name in '', 'wow', 'Wow-a', 'xwow-a', '//wow-a', 'p:wowa') {
                Test-WowName -Name $name | Should -BeFalse
            }
        }

        It 'escapes a reply' {
            Format-WowJson -EventName 'E' -Context "a`"b\c`n" | Should -BeExactly ('{"hookSpecificOutput":{"hookEventName":"E","additionalContext":"a\"b\\c\u000a"}}' + "`n")
        }

        It 'defines its functions without running when dot-sourced' {
            Get-Command -Name Invoke-WowMarker -CommandType Function | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'end to end with <Shell>' -ForEach $Shells {
        BeforeAll {
            $script:Exe = $Exe
        }

        It 'runs every mode as a script' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'

            $start = Invoke-HookFile -Exe $script:Exe -Mode 'session-start' -Cwd $other -Payload @{ session_id = 's1'; source = 'startup' }
            '{0}|{1}|{2}' -f $start.Code, $start.Out, $start.Err | Should -BeExactly '0||'

            $deny = Invoke-HookFile -Exe $script:Exe -Mode 'pre-skill' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ skill = 'wow-commits' } }
            '{0}|{1}|{2}' -f $deny.Code, $deny.Out, $deny.Err | Should -BeExactly ('2||' + $script:Deny + "`n")

            $read = Invoke-HookFile -Exe $script:Exe -Mode 'pre-tool' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ file_path = (Join-Path $repo 'a.txt') } }
            $read.Code | Should -Be 0
            $read.Err | Should -BeExactly ''
            $read.Out | Should -BeExactly ('{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"' + (Get-OnLine 'github.com/o/r') + '"}}' + "`n")
            # UTF-8 without a byte order mark.
            $read.OutBytes[0] | Should -Be ([byte][char]'{')

            $again = Invoke-HookFile -Exe $script:Exe -Mode 'pre-tool' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ file_path = (Join-Path $repo 'a.txt') } }
            '{0}|{1}|{2}' -f $again.Code, $again.Out, $again.Err | Should -BeExactly '0||'

            $post = Invoke-HookFile -Exe $script:Exe -Mode 'post-bash' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ command = 'ls' } }
            $post.Out | Should -Match ('"hookEventName":"PostToolUse","additionalContext":"' + [regex]::Escape((Get-OffLine 'github.com/o/other')))

            $allowed = Invoke-HookFile -Exe $script:Exe -Mode 'pre-skill' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ skill = 'wow-commits' } }
            '{0}|{1}|{2}' -f $allowed.Code, $allowed.Out, $allowed.Err | Should -BeExactly '0||'

            $sub = Invoke-HookFile -Exe $script:Exe -Mode 'subagent-start' -Cwd $repo -Payload @{ session_id = 's1'; agent_id = 'a1' }
            $sub.Out | Should -Match '"hookEventName":"SubagentStart"'

            $expand = Invoke-HookFile -Exe $script:Exe -Mode 'expand' -Cwd $other -Payload @{ session_id = 's1'; command_name = 'wow-commits' }
            '{0}|{1}|{2}' -f $expand.Code, $expand.Out, $expand.Err | Should -BeExactly '0||'

            $end = Invoke-HookFile -Exe $script:Exe -Mode 'session-end' -Cwd $other -Payload @{ session_id = 's1' }
            '{0}|{1}|{2}' -f $end.Code, $end.Out, $end.Err | Should -BeExactly '0||'
            @(Get-ChildItem -LiteralPath $fx.State -Force).Count | Should -Be 0

            $status = Invoke-HookFile -Exe $script:Exe -Mode 'status' -Cwd $repo
            '{0}|{1}' -f $status.Code, $status.Out | Should -BeExactly ('0|' + (Get-OnLine 'github.com/o/r') + "`n")
            $status = Invoke-HookFile -Exe $script:Exe -Mode 'status' -Cwd $other
            '{0}|{1}' -f $status.Code, $status.Out | Should -BeExactly ('1|' + (Get-OffLine 'github.com/o/other') + "`n")

            $unknown = Invoke-HookFile -Exe $script:Exe -Mode 'nonsense' -Cwd $repo -Payload @{ session_id = 's1' }
            '{0}|{1}|{2}' -f $unknown.Code, $unknown.Out, $unknown.Err | Should -BeExactly '0||'
        }

        It 'never errors or blocks on malformed input' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            foreach ($stdin in '', 'not json', '{"session_id":', '[]') {
                foreach ($mode in 'pre-tool', 'pre-skill', 'expand') {
                    $result = Invoke-HookFile -Exe $script:Exe -Mode $mode -Cwd $repo -Payload $stdin
                    # Malformed input counts as no input: stateless, so an on directory is told.
                    '{0}|{1}' -f $result.Code, $result.Err | Should -BeExactly '0|'
                }
            }
        }

        It 'needs no other program on PATH' {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $empty = Join-Path $fx.Tmp 'empty-bin'
            $null = New-Item -ItemType Directory -Path $empty
            $environment = @{ PATH = $empty }
            $start = Invoke-HookFile -Exe $script:Exe -Mode 'session-start' -Cwd $other -Payload @{ session_id = 's1' } -Environment $environment
            '{0}|{1}|{2}' -f $start.Code, $start.Out, $start.Err | Should -BeExactly '0||'
            (Invoke-HookFile -Exe $script:Exe -Mode 'pre-skill' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ skill = 'wow-commits' } } -Environment $environment).Code | Should -Be 2
            $read = Invoke-HookFile -Exe $script:Exe -Mode 'pre-tool' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ file_path = (Join-Path $repo 'a') } } -Environment $environment
            $read.Out | Should -Match ([regex]::Escape((Get-OnLine 'github.com/o/r')))
            # A held lock makes it retry, then announce anyway.
            $null = New-Item -ItemType Directory -Path (Join-Path $fx.State 's1.lock')
            $read = Invoke-HookFile -Exe $script:Exe -Mode 'pre-tool' -Cwd $other -Payload @{ session_id = 's1'; tool_input = @{ path = $other } } -Environment $environment
            $read.Out | Should -Match ([regex]::Escape((Get-OffLine 'github.com/o/other')))
            Test-Path -LiteralPath (Join-Path $fx.State 's1.lock') | Should -BeFalse
            $end = Invoke-HookFile -Exe $script:Exe -Mode 'session-end' -Cwd $other -Payload @{ session_id = 's1' } -Environment $environment
            '{0}|{1}|{2}' -f $end.Code, $end.Out, $end.Err | Should -BeExactly '0||'
        }

        It 'exits 2 through -Command without a slow exit' {
            $fx = $script:Fx
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $command = '& ''{0}'' pre-skill' -f $script:Hook.Replace('''', '''''')
            $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
            $times = @{ wow = @(); other = @() }
            foreach ($round in 1, 2) {
                foreach ($name in 'wow', 'other') {
                    $payload = @{ session_id = "s$round"; tool_input = @{ skill = "$name-commits" } }
                    $clock = [Diagnostics.Stopwatch]::StartNew()
                    $done = Invoke-HookProcess -Exe $script:Exe -Arguments $arguments -Cwd $other -Payload $payload
                    $times[$name] += $clock.ElapsedMilliseconds
                    if ($name -eq 'wow') {
                        '{0}|{1}' -f $done.Code, $done.Err.Trim() | Should -BeExactly ('2|' + $script:Deny)
                    } else {
                        '{0}|{1}' -f $done.Code, $done.Err | Should -BeExactly '0|'
                    }
                }
            }
            # [Environment]::Exit(2) made Windows PowerShell 5.1 take about 2 s more.
            $extra = ($times.wow | Measure-Object -Minimum).Minimum - ($times.other | Measure-Object -Minimum).Minimum
            $extra | Should -BeLessThan 1500
        }

        It 'runs every registered command string' -Skip:($env:OS -ne 'Windows_NT') {
            $fx = $script:Fx
            $repo = New-WsDir -Fixture $fx -Relative 'github.com/o/r' -Marker
            $other = New-WsDir -Fixture $fx -Relative 'github.com/o/other'
            $settings = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $script:WindowsDir 'settings.json')))
            $environment = @{ CLAUDE_CONFIG_DIR = $script:WindowsDir }
            $count = 0
            foreach ($eventProperty in $settings.hooks.PSObject.Properties) {
                $eventName = $eventProperty.Name
                foreach ($group in @($eventProperty.Value)) {
                    foreach ($entry in @($group.hooks)) {
                        if ($entry.command -notmatch '\\wow_marker\.ps1"') {
                            continue
                        }
                        $count++
                        $payload = @{ session_id = "s$count"; hook_event_name = $eventName; cwd = $other }
                        if ($group.matcher -eq 'Skill') {
                            $payload.tool_name = 'Skill'
                            $payload.tool_input = @{ skill = 'wow-commits' }
                        } elseif ($eventName -eq 'PreToolUse' -or $eventName -eq 'PostToolUse') {
                            $payload.tool_name = 'Bash'
                            $payload.tool_input = @{ command = 'ls' }
                        } elseif ($eventName -eq 'UserPromptExpansion') {
                            $payload.command_name = 'wow-commits'
                        }
                        $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $entry.command)
                        # From an unmarked directory: only the skill gate speaks, and it denies.
                        $done = Invoke-HookProcess -Exe $script:Exe -Arguments $arguments -Cwd $other -Payload $payload -Environment $environment
                        if ($group.matcher -eq 'Skill') {
                            '{0}|{1}' -f $done.Code, $done.Err.Trim() | Should -BeExactly ('2|' + $script:Deny)
                        } elseif ($eventName -eq 'UserPromptExpansion') {
                            $done.Code | Should -Be 0
                            $done.Out | Should -Match 'off here'
                        } else {
                            '{0}|{1}|{2}' -f $done.Code, $done.Out, $done.Err | Should -BeExactly '0||'
                        }
                        # From a marked one, the start hooks and the Bash hooks tell Claude.
                        $done = Invoke-HookProcess -Exe $script:Exe -Arguments $arguments -Cwd $repo -Payload $payload -Environment $environment
                        '{0}|{1}' -f $done.Code, $done.Err | Should -BeExactly '0|'
                        if (($eventName -in @('SessionStart', 'SubagentStart', 'PostToolUse')) -or ($eventName -eq 'PreToolUse' -and $group.matcher -ne 'Skill')) {
                            $done.Out | Should -Match ([regex]::Escape('Ways of working: on for <workspaces>/github.com/o/r'))
                        }
                    }
                }
            }
            $count | Should -Be 7
        }
    }

    Describe 'settings.json' {
        It 'registers every mode once' {
            $settings = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $script:WindowsDir 'settings.json')))
            $prefix = '& "$(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "$HOME\.claude" })\hooks\wow_marker.ps1" '
            $found = @()
            foreach ($eventProperty in $settings.hooks.PSObject.Properties) {
                foreach ($group in @($eventProperty.Value)) {
                    foreach ($entry in @($group.hooks)) {
                        if ($entry.command -notmatch 'wow_marker') {
                            continue
                        }
                        $entry.command.StartsWith($prefix) | Should -BeTrue
                        $entry.shell | Should -BeExactly 'powershell'
                        $entry.timeout | Should -Be 10
                        $found += '{0}|{1}|{2}' -f $eventProperty.Name, $group.matcher, $entry.command.Substring($prefix.Length)
                    }
                }
            }
            ($found | Sort-Object) -join "`n" | Should -BeExactly ((@(
                        'PostToolUse|Bash|post-bash'
                        'PreToolUse|Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep|Bash|Monitor|pre-tool'
                        'PreToolUse|Skill|pre-skill'
                        'SessionEnd||session-end'
                        'SessionStart||session-start'
                        'SubagentStart||subagent-start'
                        'UserPromptExpansion||expand'
                    ) | Sort-Object) -join "`n")
        }
    }
}
