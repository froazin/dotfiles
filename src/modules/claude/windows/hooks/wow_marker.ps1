<#
Claude Code ways-of-working hook for Windows: the PowerShell twin of
templates/hooks/wow_marker.sh, with the same modes, lines, replies and exit
codes. See docs/claude/ways-of-working.md.

A .wow file turns the ways of working on for the directory that holds it and
everything below, up to and including the workspace root: WORKSPACE_DIR, else
<home>/workspaces, where <home> is SUDO_HOME, else HOME, else USERPROFILE.
Each settings.json registration passes a mode, and the command strings stay
stable because the settings merge replaces hooks by command. It is pure
PowerShell and .NET, runs on PowerShell 7 and Windows PowerShell 5.1, and
starts no other program. Any error means "off" and silence: the only thing it
ever blocks is a wow-* skill, and only when nothing touched is marked.

Paths are compared case-insensitively on Windows, and resolved physically
(symbolic links and junctions followed, names in their on-disk case) the way
cd -P does. Git Bash forms (~/x, /c/x, C:/x) are read as Windows paths. A UNC
path (\\host\share, //host/share) is outside without being opened, unless the
workspace root is on that same share: the hook runs before Claude Code asks
permission, so a path in a tool call must not make Windows contact a host.

The event JSON is parsed as JSON, unlike the sh hook's sed, so escaped values
(such as C:\\Users) are decoded. Only session_id, agent_id and command_name
at the top level, and file_path, notebook_path, path and skill in tool_input,
are read, case-sensitively. Input that isn't one JSON object counts as no
fields at all.

State lives in $XDG_RUNTIME_DIR/claude-wow when XDG_RUNTIME_DIR names an
existing directory. Otherwise on Windows it lives in <temp>/claude-wow, where
<temp> is [IO.Path]::GetTempPath() (%LOCALAPPDATA%\Temp, private to the user),
and elsewhere in ${XDG_CACHE_HOME:-$HOME/.cache}/claude-wow, as in the sh hook.

Modes: session-start, subagent-start, pre-tool, post-bash, pre-skill,
expand, session-end, and status [dir] for people and tests. Dot-sourced, it
only defines its functions. Claude Code runs it with -Command, which turns a
script's exit 2 into 1, so a skill deny also sets the host's exit code.
#>

function Test-WowWindows {
    return $env:OS -eq 'Windows_NT'
}

function Get-WowHome {
    $value = $env:HOME
    if (-not $value) {
        $value = $env:USERPROFILE
    }
    return ConvertTo-WowPath -Path $value -NoTilde
}

# Rewrites a path in Git Bash form (~/x, /c/x, C:/x) or with a \\?\ prefix
# as a plain Windows path. Elsewhere it returns the path unchanged.
function ConvertTo-WowPath {
    param([string]$Path, [switch]$NoTilde)

    if (-not $Path -or -not (Test-WowWindows)) {
        return [string]$Path
    }
    if (-not $NoTilde -and ($Path -eq '~' -or $Path.StartsWith('~/') -or $Path.StartsWith('~\'))) {
        $wowHome = Get-WowHome
        if ($wowHome) {
            $Path = $wowHome + $Path.Substring(1)
        }
    }
    $drive = [regex]::Match($Path, '^/([A-Za-z])(?=/|\z)')
    if ($drive.Success) {
        $Path = $drive.Groups[1].Value.ToUpperInvariant() + ':\' + $Path.Substring(2).TrimStart('/')
    }
    $Path = $Path.Replace('/', '\')
    if ($Path.StartsWith('\\?\UNC\')) {
        $Path = '\' + $Path.Substring(7)
    } elseif ($Path.StartsWith('\\?\') -or $Path.StartsWith('\??\') -or $Path -match '^\\\\\.\\[A-Za-z]:') {
        $Path = $Path.Substring(4)
    }
    return $Path
}

# The \\host\share a Windows UNC path is on, or '' for any other path.
function Get-WowShare {
    param([string]$Path)

    if (-not $Path.StartsWith('\\') -or -not (Test-WowWindows)) {
        return ''
    }
    $parts = $Path.Substring(2).Split([char[]]@('\'), 3, [StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -lt 2) {
        return '\\' + $Path.Substring(2).Trim('\')
    }
    return '\\' + $parts[0] + '\' + $parts[1]
}

# The start of a path that a path beginning with one \ is relative to: the
# drive (C:) or the \host\share.
function Get-WowVolume {
    param([string]$Path)

    $share = Get-WowShare -Path $Path
    if ($share) {
        return $share
    }
    return $Path.Substring(0, 2)
}

# True for a UNC path that must not be opened: a device (\\.\x), or a share
# other than $Share ('*' allows any share).
function Test-WowRemote {
    param([string]$Path, [string]$Share)

    $own = Get-WowShare -Path $Path
    if (-not $own) {
        return $false
    }
    if ($own.StartsWith('\\.\') -or $own.StartsWith('\\?\') -or $own -eq '\\.' -or $own -eq '\\?') {
        return $true
    }
    if ($Share -eq '*') {
        return $false
    }
    return -not [string]::Equals($own, $Share, [StringComparison]::OrdinalIgnoreCase)
}

function Test-WowAbsolute {
    param([string]$Path)

    if (Test-WowWindows) {
        return ($Path -match '^[A-Za-z]:\\') -or ($Path -match '^\\\\[^\\]')
    }
    return $Path.StartsWith('/')
}

# Appends one name to a directory path.
function Join-WowPath {
    param([string]$Parent, [string]$Name)

    $sep = [IO.Path]::DirectorySeparatorChar
    if ($Parent.EndsWith([string]$sep)) {
        return $Parent + $Name
    }
    return $Parent + $sep + $Name
}

# The parent of a physical path, or the path itself for a root.
function Get-WowParent {
    param([string]$Path)

    $sep = [IO.Path]::DirectorySeparatorChar
    $trimmed = $Path.TrimEnd($sep)
    $i = $trimmed.LastIndexOf($sep)
    if ($i -lt 0) {
        return $Path
    }
    $parent = $trimmed.Substring(0, $i)
    if ($parent -eq '') {
        return [string]$sep
    }
    if ($parent -match '^[A-Za-z]:\z') {
        return $parent + '\'
    }
    if ($parent.StartsWith('\\') -and $parent.IndexOf('\', 2) -lt 0) {
        return $Path
    }
    return $parent
}

# The directory part of a file path: "." when it has none.
function Get-WowDirectoryName {
    param([string]$Path)

    $sep = [IO.Path]::DirectorySeparatorChar
    $i = $Path.LastIndexOf($sep)
    if ($i -lt 0) {
        return '.'
    }
    $parent = $Path.Substring(0, $i)
    if ($parent -eq '') {
        return [string]$sep
    }
    if ((Test-WowWindows) -and $parent -match '^[A-Za-z]:\z') {
        return $parent + '\'
    }
    return $parent
}

# True when a directory can be opened, following any link.
function Test-WowEnterable {
    param([string]$Path)

    try {
        $null = [IO.Directory]::GetFileSystemEntries($Path, '.wow')
        return $true
    } catch {
        return $false
    }
}

function Get-WowLinkTarget {
    param([IO.FileSystemInfo]$Info)

    # LinkTarget is .NET 6 and later (pwsh 7.2); reading it directly is
    # cheaper than asking PSObject first. Older versions ask Get-Item.
    $target = $null
    try {
        $target = $Info.LinkTarget
    } catch {
        $target = $null
    }
    if (-not $target) {
        try {
            $item = Get-Item -LiteralPath $Info.FullName -Force -ErrorAction Stop
            $target = @($item.Target)[0]
        } catch {
            $target = $null
        }
    }
    return [string]$target
}

# One step of a physical walk: the physical path of $Name inside the physical
# directory $Parent, or $null when it can't be entered. $Share is as for
# Resolve-WowPath.
function Resolve-WowChild {
    param([string]$Parent, [string]$Name, [int]$Depth, [string]$Share)

    if ($Name -eq '.') {
        return $Parent
    }
    if ($Name -eq '..') {
        return Get-WowParent -Path $Parent
    }
    if (Test-WowWindows) {
        # Windows forbids these in a name: wildcards (DOS ones included)
        # would match other names, and a trailing dot or space is dropped.
        if ($Name -match '[\x00-\x1F*?<>"|:]|[. ]\z') {
            return $null
        }
        try {
            $found = @(([IO.DirectoryInfo]::new($Parent)).GetDirectories($Name))
        } catch {
            return $null
        }
        if ($found.Count -eq 0) {
            return $null
        }
        # The on-disk name, in its own case, rather than a short (8.3) name.
        $info = $found[0]
        foreach ($entry in $found) {
            if ($entry.Name -eq $Name) {
                $info = $entry
                break
            }
        }
        $candidate = Join-WowPath -Parent $Parent -Name $info.Name
    } else {
        $candidate = Join-WowPath -Parent $Parent -Name $Name
        if (-not [IO.Directory]::Exists($candidate)) {
            return $null
        }
        $info = [IO.DirectoryInfo]::new($candidate)
    }
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        return $candidate
    }

    # A symbolic link or junction: walk its target instead. The root, the
    # session directory and the target often share one, so Invoke-WowMarker
    # keeps what each link resolved to for the rest of the call.
    $cache = $script:WowLinkCache
    $key = $Share + '|' + $candidate
    if ($null -ne $cache -and $cache.ContainsKey($key)) {
        return $cache[$key]
    }
    $target = ConvertTo-WowPath -Path (Get-WowLinkTarget -Info $info) -NoTilde
    if ($target) {
        if ((Test-WowWindows) -and $target.StartsWith('\') -and -not $target.StartsWith('\\')) {
            $target = (Get-WowVolume -Path $Parent) + $target
        } elseif (-not (Test-WowAbsolute -Path $target)) {
            $target = Join-WowPath -Parent $Parent -Name $target
        }
        $resolved = Resolve-WowPath -Path $target -Depth ($Depth + 1) -Share $Share
        if ($null -ne $resolved) {
            if ($null -ne $cache) {
                $cache[$key] = $resolved
            }
            return $resolved
        }
        if (Test-WowRemote -Path $target -Share $Share) {
            # Opening the link would contact another host.
            return $null
        }
    }
    # Another kind of reparse point (such as a mount point or a cloud file)
    # that opens is a directory; a dangling or looping link is not.
    if (Test-WowEnterable -Path $candidate) {
        return $candidate
    }
    return $null
}

# The physical path of an absolute directory, as cd -P leaves in PWD, or
# $null when it can't be entered. With -Partial, a path that can't be entered
# counts as its longest prefix that can. A UNC path on a share other than
# $Share ('*' for any) is never opened: it comes back as it is, which is
# outside the root, or $null for a device path.
function Resolve-WowPath {
    param([string]$Path, [switch]$Partial, [int]$Depth = 0, [string]$Share = '')

    if ($Depth -gt 40 -or -not (Test-WowAbsolute -Path $Path)) {
        return $null
    }
    $sep = [IO.Path]::DirectorySeparatorChar
    if (-not (Test-WowWindows)) {
        $root = '/'
        $rest = $Path
    } elseif ($Path.StartsWith('\\')) {
        if (Test-WowRemote -Path $Path -Share $Share) {
            if ((Test-WowRemote -Path $Path -Share '*')) {
                return $null
            }
            return $Path
        }
        $parts = $Path.Substring(2).Split([char[]]@('\'), 3, [StringSplitOptions]::RemoveEmptyEntries)
        if ($parts.Count -lt 2) {
            return $null
        }
        $root = '\\' + $parts[0] + '\' + $parts[1]
        $rest = ''
        if ($parts.Count -gt 2) {
            $rest = $parts[2]
        }
    } else {
        $root = $Path.Substring(0, 1).ToUpperInvariant() + ':\'
        $rest = $Path.Substring(3)
    }
    if (-not [IO.Directory]::Exists($root)) {
        return $null
    }

    $current = $root
    foreach ($name in $rest.Split([char[]]@($sep), [StringSplitOptions]::RemoveEmptyEntries)) {
        $next = Resolve-WowChild -Parent $current -Name $name -Depth $Depth -Share $Share
        if ($null -eq $next) {
            if ($Partial) {
                return $current
            }
            return $null
        }
        if (Test-WowRemote -Path $next -Share $Share) {
            # A link to another share: outside, and never opened.
            return $next
        }
        $current = $next
    }
    return $current
}

# True when $Path is a .wow marker: a file, following any link the way sh's
# -f does. A link to another share counts as no marker, unopened.
function Test-WowMarker {
    param([string]$Path, [string]$Share, [int]$Depth = 0)

    if ($Depth -gt 40) {
        return $false
    }
    $isFile = [IO.File]::Exists($Path)
    if (-not $isFile -and -not [IO.Directory]::Exists($Path)) {
        return $false
    }
    try {
        $attributes = [IO.File]::GetAttributes($Path)
    } catch {
        return $false
    }
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
        return $isFile
    }
    $info = [IO.FileInfo]::new($Path)
    $target = ConvertTo-WowPath -Path (Get-WowLinkTarget -Info $info) -NoTilde
    if (-not $target) {
        # Another kind of reparse point, such as a cloud file.
        return $isFile
    }
    $parent = Get-WowDirectoryName -Path $Path
    if ((Test-WowWindows) -and $target.StartsWith('\') -and -not $target.StartsWith('\\')) {
        $target = (Get-WowVolume -Path $parent) + $target
    } elseif (-not (Test-WowAbsolute -Path $target)) {
        $target = Join-WowPath -Parent $parent -Name $target
    }
    if (Test-WowRemote -Path $target -Share $Share) {
        return $false
    }
    return Test-WowMarker -Path $target -Share $Share -Depth ($Depth + 1)
}

# The physical workspace root, or $null when it is relative or missing.
function Get-WowRoot {
    $root = $env:WORKSPACE_DIR
    if (-not $root) {
        $parent = $env:SUDO_HOME
        if (-not $parent) {
            $parent = Get-WowHome
        }
        $root = [string]$parent + '/workspaces'
    }
    $root = ConvertTo-WowPath -Path $root
    if (-not (Test-WowAbsolute -Path $root)) {
        return $null
    }
    return Resolve-WowPath -Path $root -Share '*'
}

# <workspaces>/<rel>, or $null when rel holds a character that would need
# escaping in JSON (or that could leak more than a path should).
function Get-WowShown {
    param([string]$Relative)

    if ($Relative -cmatch '[^A-Za-z0-9._/@+-]') {
        return $null
    }
    if ($Relative -eq '') {
        return '<workspaces>'
    }
    return '<workspaces>/' + $Relative
}

# The state for one directory, relative to the session directory when it
# isn't absolute: On, Key (on:<rel marker dir> or off) and Line.
function Find-WowMarker {
    param([string]$Directory, [string]$Start, [string]$Root)

    $result = @{ On = $false; Key = 'off'; Line = 'Ways of working: off (outside <workspaces>).' }
    if (-not $Root) {
        return $result
    }
    $windows = Test-WowWindows
    $sep = [IO.Path]::DirectorySeparatorChar

    $path = ConvertTo-WowPath -Path $Directory
    if (-not (Test-WowAbsolute -Path $path)) {
        # The session directory may be gone, such as a removed worktree.
        if (-not $Start) {
            return $result
        }
        if ($windows -and $path.StartsWith('\')) {
            $path = (Get-WowVolume -Path $Start) + $path
        } else {
            $path = Join-WowPath -Parent $Start -Name $path
        }
    }
    # A missing directory (such as a Write that creates one) counts as its
    # nearest existing ancestor.
    $share = Get-WowShare -Path $Root
    $dir = Resolve-WowPath -Path $path -Partial -Share $share
    if ($null -eq $dir) {
        return $result
    }

    $compare = [StringComparison]::Ordinal
    if ($windows) {
        $compare = [StringComparison]::OrdinalIgnoreCase
    }
    $prefix = $Root
    if (-not $prefix.EndsWith([string]$sep)) {
        $prefix += $sep
    }
    if ([string]::Equals($dir, $Root, $compare)) {
        $relative = ''
    } elseif ($dir.StartsWith($prefix, $compare)) {
        $relative = $dir.Substring($prefix.Length)
    } else {
        return $result
    }

    $marker = $relative
    while ($true) {
        $here = $Root
        if ($marker) {
            $here = $prefix + $marker
        }
        if (Test-WowMarker -Path (Join-WowPath -Parent $here -Name '.wow') -Share $share) {
            break
        }
        if (-not $marker) {
            $shown = Get-WowShown -Relative $relative.Replace($sep, '/')
            if ($null -ne $shown) {
                $result.Line = "Ways of working: off for $shown (no .wow marker at or above it)."
            } else {
                $result.Line = 'Ways of working: off (no .wow marker at or above this directory).'
            }
            return $result
        }
        $i = $marker.LastIndexOf($sep)
        if ($i -lt 0) {
            $marker = ''
        } else {
            $marker = $marker.Substring(0, $i)
        }
    }

    $marker = $marker.Replace($sep, '/')
    $result.On = $true
    $shown = Get-WowShown -Relative $marker
    if ($null -ne $shown) {
        $result.Key = 'on:' + $marker
        $result.Line = "Ways of working: on for $shown (marker $shown/.wow)."
    } else {
        # The state file holds one line, and such a path may hold a newline.
        $result.Key = 'on:?'
        $result.Line = 'Ways of working: on (marker found).'
    }
    return $result
}

function Get-WowString {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object -or $Object -isnot [Management.Automation.PSCustomObject]) {
        return ''
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Name -cne $Name -or $property.Value -isnot [string]) {
        return ''
    }
    return $property.Value
}

# The fields the hook uses from the event JSON. Anything missing, not a
# string, or in input that doesn't parse counts as absent ('').
function Read-WowInput {
    param([byte[]]$Bytes)

    $fields = @{ SessionId = ''; AgentId = ''; File = ''; Path = ''; Skill = ''; CommandName = '' }
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return $fields
    }
    try {
        $text = ([Text.UTF8Encoding]::new($false)).GetString($Bytes).TrimStart([char]0xFEFF)
        if (-not $text.TrimStart().StartsWith('{')) {
            # Not one object: pwsh would unroll a one-item array, 5.1 not.
            return $fields
        }
        $hookEvent = ConvertFrom-Json -InputObject $text -ErrorAction Stop
    } catch {
        return $fields
    }
    $tool = $null
    if ($hookEvent -is [Management.Automation.PSCustomObject]) {
        $property = $hookEvent.PSObject.Properties['tool_input']
        if ($null -ne $property -and $property.Name -ceq 'tool_input') {
            $tool = $property.Value
        }
    }
    $fields.SessionId = Get-WowString -Object $hookEvent -Name 'session_id'
    $fields.AgentId = Get-WowString -Object $hookEvent -Name 'agent_id'
    $fields.CommandName = Get-WowString -Object $hookEvent -Name 'command_name'
    $fields.File = Get-WowString -Object $tool -Name 'file_path'
    if (-not $fields.File) {
        $fields.File = Get-WowString -Object $tool -Name 'notebook_path'
    }
    $fields.Path = Get-WowString -Object $tool -Name 'path'
    $fields.Skill = Get-WowString -Object $tool -Name 'skill'
    return $fields
}

function New-WowDirectory {
    param([string]$Path)

    if ([IO.Directory]::Exists($Path)) {
        return
    }
    if (Test-WowWindows) {
        # A new directory under %LOCALAPPDATA%\Temp inherits its ACL, which
        # already keeps other users out.
        $null = [IO.Directory]::CreateDirectory($Path)
        return
    }
    $parent = [IO.Path]::GetDirectoryName($Path)
    if ($parent -and -not [IO.Directory]::Exists($parent)) {
        $null = [IO.Directory]::CreateDirectory($parent)
    }
    # Mode 0700 where .NET can set it (7.3 and later). Another hook may
    # create it first.
    $modeType = [Type]::GetType('System.IO.UnixFileMode')
    $create = $null
    if ($modeType) {
        $create = [IO.Directory].GetMethod('CreateDirectory', [Type[]]@([string], $modeType))
    }
    if ($create) {
        $null = $create.Invoke($null, @($Path, [Enum]::ToObject($modeType, 448)))
    } else {
        $null = [IO.Directory]::CreateDirectory($Path)
    }
}

# The state directory, or $null (stateless) when none can be used.
function Get-WowStateDirectory {
    $candidates = @()
    $runtime = ConvertTo-WowPath -Path $env:XDG_RUNTIME_DIR -NoTilde
    if ($runtime -and (Test-WowAbsolute -Path $runtime) -and [IO.Directory]::Exists($runtime)) {
        $candidates += Join-WowPath -Parent $runtime -Name 'claude-wow'
    }
    if (Test-WowWindows) {
        $candidates += Join-WowPath -Parent ([IO.Path]::GetTempPath()) -Name 'claude-wow'
    } else {
        $cache = $env:XDG_CACHE_HOME
        if (-not $cache) {
            $cache = [string]$env:HOME + '/.cache'
        }
        $candidates += Join-WowPath -Parent $cache -Name 'claude-wow'
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-WowAbsolute -Path $candidate)) {
            continue
        }
        try {
            New-WowDirectory -Path $candidate
            if ([IO.Directory]::Exists($candidate)) {
                return $candidate
            }
        } catch {
            continue
        }
    }
    return $null
}

# This session's file prefix in the state directory, or $null (stateless)
# for an unsafe id or no usable directory.
function Get-WowStateBase {
    param([string]$SessionId)

    if ($SessionId -cnotmatch '^[A-Za-z0-9_-]+\z') {
        return $null
    }
    $dir = Get-WowStateDirectory
    if (-not $dir) {
        return $null
    }
    return Join-WowPath -Parent $dir -Name $SessionId
}

# The state file for this session, or for this subagent inside it, or $null
# when the agent id is unsafe.
function Get-WowStateFile {
    param([string]$Base, [string]$AgentId)

    if (-not $AgentId) {
        return $Base + '.state'
    }
    if ($AgentId -cnotmatch '^[A-Za-z0-9_-]+\z') {
        return $null
    }
    return $Base + '.' + $AgentId + '.state'
}

# The key in a state file; a missing one counts as off.
function Read-WowState {
    param([string]$Path)

    $key = ''
    try {
        if ([IO.File]::Exists($Path)) {
            $key = [IO.File]::ReadAllText($Path).Split([char]10)[0].Trim()
        }
    } catch {
        $key = ''
    }
    if (-not $key) {
        $key = 'off'
    }
    return $key
}

function Write-WowState {
    param([string]$Path, [string]$Key)

    try {
        [IO.File]::WriteAllText($Path, $Key + "`n", [Text.UTF8Encoding]::new($false))
    } catch {
        # Left as it was, so the next call announces again.
        $Path = $null
    }
}

function Set-WowFlag {
    param([string]$Base)

    try {
        [IO.File]::WriteAllBytes($Base + '.on', [byte[]]@())
    } catch {
        $Base = $null
    }
}

# Takes the lock: Locked, Held (by another hook, or left by a killed one) or
# Denied (the state directory can't be written, so there's no state).
function Lock-WowState {
    param([string]$Path)

    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        return 'Locked'
    } catch [UnauthorizedAccessException] {
        # Windows also says this for a lock directory, which is held.
        if ([IO.Directory]::Exists($Path) -or [IO.File]::Exists($Path)) {
            return 'Held'
        }
        return 'Denied'
    } catch {
        return 'Held'
    }
}

# Removes a lock file, or an empty lock directory such as the sh hook takes.
function Unlock-WowState {
    param([string]$Path)

    try {
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Delete($Path)
        } elseif ([IO.Directory]::Exists($Path)) {
            [IO.Directory]::Delete($Path)
        }
    } catch {
        $Path = $null
    }
}

# Records the key for a directory. Tell is true when it changed (or when
# there's no state to compare with and it's on). A missing state counts as
# off, the state before any line.
function Update-WowState {
    param([string]$Directory, [hashtable]$Context)

    $found = Find-WowMarker -Directory $Directory -Start $Context.Start -Root $Context.Root
    $base = Get-WowStateBase -SessionId $Context.SessionId
    $file = $null
    if ($base) {
        $file = Get-WowStateFile -Base $base -AgentId $Context.AgentId
    }
    if (-not $file) {
        return @{ Tell = $found.On; Line = $found.Line }
    }
    if ((Read-WowState -Path $file) -ceq $found.Key) {
        return @{ Tell = $false; Line = $found.Line }
    }

    $lock = $base + '.lock'
    $locked = 'Held'
    for ($try = 1; $try -le 20; $try++) {
        $locked = Lock-WowState -Path $lock
        if ($locked -ne 'Held') {
            break
        }
        if ($try -lt 20) {
            [Threading.Thread]::Sleep(50)
        }
    }
    if ($locked -eq 'Denied') {
        # An unwritable state directory: stateless, as the sh hook's [ -w ]
        # check makes it, without waiting for a lock it can never take.
        return @{ Tell = $found.On; Line = $found.Line }
    }
    if ($locked -eq 'Held') {
        # Fail towards telling Claude, and clear what is most likely a lock
        # left by a killed hook.
        if ($found.On) {
            Set-WowFlag -Base $base
        }
        Unlock-WowState -Path $lock
        return @{ Tell = $true; Line = $found.Line }
    }

    $tell = $false
    try {
        if ((Read-WowState -Path $file) -cne $found.Key) {
            Write-WowState -Path $file -Key $found.Key
            $tell = $true
        }
        if ($found.On) {
            Set-WowFlag -Base $base
        }
    } finally {
        Unlock-WowState -Path $lock
    }
    return @{ Tell = $tell; Line = $found.Line }
}

# Starts a session or a subagent: records the state for the session
# directory, replacing any earlier one.
function Initialize-WowState {
    param([hashtable]$Context)

    $found = Find-WowMarker -Directory $Context.Start -Start $Context.Start -Root $Context.Root
    $base = Get-WowStateBase -SessionId $Context.SessionId
    if (-not $base) {
        return $found
    }
    $file = Get-WowStateFile -Base $base -AgentId $Context.AgentId
    if (-not $file) {
        return $found
    }
    Write-WowState -Path $file -Key $found.Key
    if ($found.On) {
        Set-WowFlag -Base $base
    }
    return $found
}

# Removes this session's files. False when it has no state.
function Reset-WowState {
    param([string]$SessionId)

    $base = Get-WowStateBase -SessionId $SessionId
    if (-not $base) {
        return $false
    }
    $compare = [StringComparison]::Ordinal
    if (Test-WowWindows) {
        $compare = [StringComparison]::OrdinalIgnoreCase
    }
    $dir = [IO.Path]::GetDirectoryName($base)
    foreach ($entry in [IO.Directory]::GetFileSystemEntries($dir, $SessionId + '.*')) {
        if (-not [IO.Path]::GetFileName($entry).StartsWith($SessionId + '.', $compare)) {
            continue
        }
        try {
            if ([IO.File]::Exists($entry)) {
                [IO.File]::Delete($entry)
            } elseif (([IO.File]::GetAttributes($entry) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                # A link is removed, never what it points to.
                [IO.Directory]::Delete($entry)
            } else {
                [IO.Directory]::Delete($entry, $true)
            }
        } catch {
            continue
        }
    }
    return $true
}

function Test-WowName {
    param([string]$Name)

    if ($Name.StartsWith('/')) {
        $Name = $Name.Substring(1)
    }
    return ($Name -clike 'wow-*') -or ($Name -clike '*:wow-*')
}

# Allowed when a touched directory was on, or the session directory is on.
function Test-WowAllowed {
    param([hashtable]$Context)

    $base = Get-WowStateBase -SessionId $Context.SessionId
    if ($base -and ([IO.File]::Exists($base + '.on') -or [IO.Directory]::Exists($base + '.on'))) {
        return $true
    }
    return (Find-WowMarker -Directory $Context.Start -Start $Context.Start -Root $Context.Root).On
}

function Format-WowJson {
    param([string]$EventName, [string]$Context)

    $escaped = [Text.StringBuilder]::new()
    foreach ($c in $Context.ToCharArray()) {
        if ($c -eq '"' -or $c -eq '\') {
            $null = $escaped.Append('\').Append($c)
        } elseif ([int]$c -lt 32) {
            $null = $escaped.Append('\u').Append(([int]$c).ToString('x4'))
        } else {
            $null = $escaped.Append($c)
        }
    }
    return '{"hookSpecificOutput":{"hookEventName":"' + $EventName + '","additionalContext":"' + $escaped.ToString() + '"}}' + "`n"
}

# Runs one mode. $Directory is Claude's current directory, and $InputBytes
# the event JSON. Returns Code, Out (stdout) and Err (stderr).
function Invoke-WowMarker {
    param([string]$Mode, [string]$Argument, [byte[]]$InputBytes, [string]$Directory)

    $result = @{ Code = 0; Out = ''; Err = '' }
    $script:WowLinkCache = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $root = Get-WowRoot
    $start = ''
    $current = ConvertTo-WowPath -Path $Directory
    if (Test-WowAbsolute -Path $current) {
        $resolved = Resolve-WowPath -Path $current -Share (Get-WowShare -Path $root)
        if ($resolved) {
            $start = $resolved
        }
    }
    $context = @{ Start = $start; Root = $root; SessionId = ''; AgentId = '' }
    if ($Mode -cne 'status') {
        $fields = Read-WowInput -Bytes $InputBytes
        $context.SessionId = $fields.SessionId
        $context.AgentId = $fields.AgentId
    }

    switch -CaseSensitive ($Mode) {
        'status' {
            $target = $Argument
            if (-not $target) {
                $target = $start
            }
            $found = Find-WowMarker -Directory $target -Start $start -Root $context.Root
            $result.Out = $found.Line + "`n"
            if (-not $found.On) {
                $result.Code = 1
            }
        }
        'session-start' {
            $context.AgentId = ''
            $null = Reset-WowState -SessionId $context.SessionId
            $found = Initialize-WowState -Context $context
            if ($found.On) {
                $result.Out = $found.Line + "`n"
            }
        }
        'subagent-start' {
            $found = Initialize-WowState -Context $context
            if ($found.On) {
                $result.Out = Format-WowJson -EventName 'SubagentStart' -Context $found.Line
            }
        }
        'pre-tool' {
            if ($fields.File) {
                $target = Get-WowDirectoryName -Path (ConvertTo-WowPath -Path $fields.File)
            } elseif ($fields.Path) {
                $target = $fields.Path
            } else {
                $target = '.'
            }
            $tracked = Update-WowState -Directory $target -Context $context
            if ($tracked.Tell) {
                $result.Out = Format-WowJson -EventName 'PreToolUse' -Context $tracked.Line
            }
        }
        'post-bash' {
            $tracked = Update-WowState -Directory $start -Context $context
            if ($tracked.Tell) {
                $result.Out = Format-WowJson -EventName 'PostToolUse' -Context $tracked.Line
            }
        }
        'pre-skill' {
            if ((Test-WowName -Name $fields.Skill) -and -not (Test-WowAllowed -Context $context)) {
                $result.Err = "Ways of working is off: no directory touched in this session has a .wow marker, so wow-* skills don't apply.`n"
                $result.Code = 2
            }
        }
        'expand' {
            if ((Test-WowName -Name $fields.CommandName) -and -not (Test-WowAllowed -Context $context)) {
                $name = $fields.CommandName
                if ($name.StartsWith('/')) {
                    $name = $name.Substring(1)
                }
                if ($name -cmatch '[^A-Za-z0-9._:@+-]') {
                    $note = 'The user typed the command explicitly.'
                } else {
                    $note = "The user typed /$name explicitly."
                }
                $result.Out = Format-WowJson -EventName 'UserPromptExpansion' -Context "Ways of working: off here (no .wow marker). $note"
            }
        }
        'session-end' {
            $null = Reset-WowState -SessionId $context.SessionId
        }
    }
    $script:WowLinkCache = $null
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    $wowCode = 0
    try {
        Set-StrictMode -Off
        $ErrorActionPreference = 'Stop'
        $wowMode = ''
        $wowArgument = ''
        if ($args.Count -gt 0) {
            $wowMode = [string]$args[0]
        }
        if ($args.Count -gt 1) {
            $wowArgument = [string]$args[1]
        }
        $wowBytes = $null
        $wowModes = @('session-start', 'subagent-start', 'pre-tool', 'post-bash', 'pre-skill', 'expand', 'session-end')
        if ($wowModes -ccontains $wowMode) {
            $wowStream = [IO.MemoryStream]::new()
            [Console]::OpenStandardInput().CopyTo($wowStream)
            $wowBytes = $wowStream.ToArray()
        }
        $wowDirectory = ''
        try {
            $wowDirectory = [IO.Directory]::GetCurrentDirectory()
        } catch {
            $wowDirectory = ''
        }
        $wowResult = Invoke-WowMarker -Mode $wowMode -Argument $wowArgument -InputBytes $wowBytes -Directory $wowDirectory
        $wowEncoding = [Text.UTF8Encoding]::new($false)
        if ($wowResult.Out) {
            $wowOut = $wowEncoding.GetBytes($wowResult.Out)
            $wowStdout = [Console]::OpenStandardOutput()
            $wowStdout.Write($wowOut, 0, $wowOut.Length)
            $wowStdout.Flush()
        }
        if ($wowResult.Err) {
            $wowErr = $wowEncoding.GetBytes($wowResult.Err)
            $wowStderr = [Console]::OpenStandardError()
            $wowStderr.Write($wowErr, 0, $wowErr.Length)
            $wowStderr.Flush()
        }
        $wowCode = $wowResult.Code
    } catch {
        exit 0
    }
    if ($wowCode -eq 2) {
        # Claude Code runs the hook with -Command, which turns any exit code
        # but 0 from a script into 1, and only 2 blocks the skill. Setting
        # the host's exit code keeps the 2; [Environment]::Exit(2) would too,
        # but adds about 2 s to Windows PowerShell 5.1's exit.
        $Host.SetShouldExit(2)
    }
    exit $wowCode
}
