<#
Claude Code hook: keep Claude Code session links out of everything published.

The PowerShell twin of templates/hooks/no_session_links.py, which Claude Code
runs on Windows: the same decisions, the same reply JSON and exit code, and
the same fail-open rule. Read docs/claude/no-session-links.md before you
change it, and change the two together.

PreToolUse only. Denies a tool call that would put a link to a Claude Code
session, a Claude-Session trailer or a claude.ai artifact link into a commit,
tag, pull request, issue, comment, file or MCP call:

  Bash, Monitor   the command text, files passed as a message or body
                  (git -F/--file, gh --body-file/-F/--notes-file), and on
                  git push, the messages of commits no remote has yet
  Write, Edit,    the text being written
  MultiEdit,
  NotebookEdit
  mcp__*          the whole tool input

It is a guard rail against Claude Code's attribution habits, not a security
boundary. Pure PowerShell that runs on Windows PowerShell 5.1 and PowerShell 7
(on Windows or Linux), and starts no process but git log on git push, as the
reference does. It keeps no state. Any internal error fails open: exit 0 and
nothing printed.

On Windows, a path in a command may be ~/x, /c/Users/u/x, C:/Users/u/x or a
quoted C:\Users\u\x, and /tmp is $env:TEMP, where Git for Windows mounts it.
Home is $env:HOME when it's set, else $env:USERPROFILE.

Dot-source this file to define its functions without running the hook.
#>

# Flags whose next argument is a file holding a commit message or body.
function Get-MessageFileFlag {
    $flags = [string[]]@('-F', '--file', '--body-file', '--notes-file')
    return , [System.Collections.Generic.HashSet[string]]::new($flags, [System.StringComparer]::Ordinal)
}

# The characters Python's str.strip() and str.split() treat as whitespace:
# .NET's Char.IsWhiteSpace plus U+001C to U+001F.
function Get-PythonWhitespace {
    $codes = @(0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0, 0x1680)
    $codes += 0x2000..0x200A
    $codes += @(0x2028, 0x2029, 0x202F, 0x205F, 0x3000)
    return , [char[]]$codes
}

# The reference's patterns, in its order, spelt so .NET matches what Python's
# re does. Its case-insensitive trailer also takes U+0130 and U+0131 for i
# and U+017F for s, its \b counts letters, digits and _ as word characters,
# and its \s includes U+001C to U+001F.
function Get-LinkPattern {
    $plain = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $lines = [System.Text.RegularExpressions.RegexOptions]'Multiline, CultureInvariant'
    $trailer = '^[ \t]*[Cc][Ll][Aa][Uu][Dd][Ee]-[Ss\u017f][Ee][Ss\u017f][Ss\u017f][Ii\u0130\u0131][Oo][Nn]:[ \t]*[^\s\x1c-\x1f]'
    return , @(
        @('a Claude Code session URL', [regex]::new('claude\.ai/code/session_[A-Za-z0-9]', $plain)),
        @('a claude.ai artifact link', [regex]::new('claude\.ai/(?:code/)?artifact/[A-Za-z0-9]', $plain)),
        @('a Claude-Session trailer', [regex]::new($trailer, $lines)),
        @('a Claude Code session ID', [regex]::new('(?<![\p{L}\p{N}_])session_[A-Za-z0-9]{24,}(?![\p{L}\p{N}_])', $plain))
    )
}

function Test-WindowsHost {
    return $env:OS -eq 'Windows_NT'
}

# The first $Count code points of $Text, as Python's [:120] slices.
function Limit-CodePoint {
    param([string]$Text, [int]$Count)

    if ($Text.Length -le $Count) {
        return $Text
    }
    $i = 0
    $n = 0
    while ($i -lt $Text.Length -and $n -lt $Count) {
        if ([char]::IsHighSurrogate($Text[$i]) -and $i + 1 -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])) {
            $i += 2
        } else {
            $i += 1
        }
        $n += 1
    }
    return $Text.Substring(0, $i)
}

# The first link in $Text: what it is, and the line it is on. $null if none.
function Find-SessionLink {
    param([string]$Text)

    foreach ($pattern in (Get-LinkPattern)) {
        $match = $pattern[1].Match($Text)
        if (-not $match.Success) {
            continue
        }
        $start = 0
        if ($match.Index -gt 0) {
            $start = $Text.LastIndexOf([char]10, $match.Index - 1) + 1
        }
        $end = $Text.IndexOf([char]10, $start)
        if ($end -lt 0) {
            $end = $Text.Length
        }
        $line = $Text.Substring($start, $end - $start).Trim((Get-PythonWhitespace))
        return , @($pattern[0], (Limit-CodePoint -Text $line -Count 120))
    }
    return $null
}

# JSON input, read the way Python's json.loads reads it, into
# Dictionary[string, object] (ordered, case-sensitive keys), List[object],
# string, bool, $null, and numbers as objects whose PythonJson property is
# how Python's json.dumps writes them back. Throws on anything Python rejects.
function ConvertFrom-HookJson {
    param([string]$Text)

    $lexer = [regex]::new('\G[ \t\n\r]*(?:("(?>(?:[^"\\\x00-\x1f]+|\\["\\/bfnrt]|\\u[0-9a-fA-F]{4})*)")|(-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?)|([{}\[\]:,])|(true|false|null|NaN|Infinity|-Infinity))')
    $stack = [System.Collections.Generic.List[object]]::new()
    $root = $null
    # value, firstValue (or ]), key, firstKey (or }), colon, next (, or close) or done
    $state = 'value'
    $pos = 0
    foreach ($token in $lexer.Matches($Text)) {
        $pos = $token.Index + $token.Length
        $value = $null
        if ($token.Groups[5].Success) {
            $mark = $token.Groups[5].Value
            $top = $null
            if ($stack.Count -gt 0) {
                $top = $stack[$stack.Count - 1]
            }
            if (($mark -ceq '{' -or $mark -ceq '[') -and ($state -ceq 'value' -or $state -ceq 'firstValue')) {
                if ($mark -ceq '{') {
                    $container = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
                    $state = 'firstKey'
                } else {
                    $container = [System.Collections.Generic.List[object]]::new()
                    $state = 'firstValue'
                }
                $stack.Add(@{ Container = $container; Key = $null; IsObject = ($mark -ceq '{') })
                continue
            }
            if ($mark -ceq ':' -and $state -ceq 'colon') {
                $state = 'value'
                continue
            }
            if ($mark -ceq ',' -and $state -ceq 'next') {
                if ($top.IsObject) {
                    $state = 'key'
                } else {
                    $state = 'value'
                }
                continue
            }
            $closesObject = $mark -ceq '}' -and ($state -ceq 'next' -or $state -ceq 'firstKey') -and $top.IsObject
            $closesArray = $mark -ceq ']' -and ($state -ceq 'next' -or $state -ceq 'firstValue') -and $null -ne $top -and -not $top.IsObject
            if (-not ($closesObject -or $closesArray)) {
                throw 'Unexpected JSON punctuation'
            }
            $stack.RemoveAt($stack.Count - 1)
            $value = $top.Container
        } elseif ($token.Groups[1].Success) {
            $value = ConvertFrom-JsonStringToken -Token $token.Groups[1].Value
            if ($state -ceq 'key' -or $state -ceq 'firstKey') {
                $stack[$stack.Count - 1].Key = $value
                $state = 'colon'
                continue
            }
            if ($state -cne 'value' -and $state -cne 'firstValue') {
                throw 'Unexpected JSON string'
            }
        } else {
            if ($state -cne 'value' -and $state -cne 'firstValue') {
                throw 'Unexpected JSON value'
            }
            if ($token.Groups[2].Success) {
                $isFloat = $token.Groups[3].Success -or $token.Groups[4].Success
                $value = [pscustomobject]@{ PythonJson = (Format-JsonNumber -Text $token.Groups[2].Value -IsFloat $isFloat) }
            } else {
                switch -CaseSensitive ($token.Groups[6].Value) {
                    'true' { $value = $true }
                    'false' { $value = $false }
                    'null' { $value = $null }
                    default { $value = [pscustomobject]@{ PythonJson = $token.Groups[6].Value } }
                }
            }
        }

        if ($stack.Count -eq 0) {
            $root = $value
            $state = 'done'
        } else {
            $top = $stack[$stack.Count - 1]
            if ($top.IsObject) {
                $top.Container[$top.Key] = $value
            } else {
                $top.Container.Add($value)
            }
            $state = 'next'
        }
    }
    if ($state -cne 'done' -or -not [regex]::IsMatch($Text.Substring($pos), '\A[ \t\n\r]*\z')) {
        throw 'Not a JSON document'
    }
    return , $root
}

function ConvertFrom-JsonStringToken {
    param([string]$Token)

    $body = $Token.Substring(1, $Token.Length - 2)
    if ($body.IndexOf([char]'\') -lt 0) {
        return $body
    }
    $unescape = [System.Text.RegularExpressions.MatchEvaluator] {
        param($escape)
        if ($escape.Groups[1].Success) {
            return [string][char][System.Convert]::ToInt32($escape.Groups[1].Value, 16)
        }
        switch -CaseSensitive ($escape.Groups[2].Value) {
            'b' { return [string][char]8 }
            'f' { return [string][char]12 }
            'n' { return [string][char]10 }
            'r' { return [string][char]13 }
            't' { return [string][char]9 }
            default { return $escape.Groups[2].Value }
        }
    }
    return [regex]::Replace($body, '\\(?:u([0-9a-fA-F]{4})|(.))', $unescape)
}

# A decimal number as the nearest double (ties to even), as Python's float()
# reads it. Worked out exactly with BigInteger, because .NET Framework's
# Double.Parse rounds some long inputs wrongly and throws OverflowException
# for some just under [double]::MaxValue.
function ConvertFrom-FloatText {
    param([string]$Text)

    $parts = [regex]::Match($Text, '\A(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([-+]?[0-9]+))?\z')
    if (-not $parts.Success) {
        throw 'Not a decimal number'
    }
    $digits = ($parts.Groups[2].Value + $parts.Groups[3].Value).TrimStart('0')
    $magnitude = 0.0
    if ($digits -cne '') {
        $exponentText = $parts.Groups[4].Value.TrimStart('+')
        $huge = $exponentText.TrimStart('-').TrimStart('0').Length -gt 9
        $power = 0 - $parts.Groups[3].Value.Length
        if (-not $huge -and $exponentText -cne '') {
            $power += [long]$exponentText
        }
        # The value is 0.<digits> times 10 to the power $point.
        $point = $digits.Length + $power
        if (($huge -and -not $exponentText.StartsWith('-', [System.StringComparison]::Ordinal)) -or $point -gt 310) {
            $magnitude = [double]::PositiveInfinity
        } elseif (-not $huge -and $point -ge -330) {
            $magnitude = ConvertFrom-DecimalPart -Digit $digits -Power ([int]$power)
        }
    }
    if ($parts.Groups[1].Value -ceq '-') {
        return $magnitude * -1
    }
    return $magnitude
}

# <Digit> times 10 to the power $Power, rounded to the nearest double, ties
# to even, subnormals included.
function ConvertFrom-DecimalPart {
    param([string]$Digit, [int]$Power)

    $big = [System.Numerics.BigInteger]
    $numerator = $big::Parse($Digit)
    $denominator = $big::One
    if ($Power -ge 0) {
        $numerator *= $big::Pow(10, $Power)
    } else {
        $denominator = $big::Pow(10, 0 - $Power)
    }
    $top = $big::Pow(2, 53)
    $bottom = $big::Pow(2, 52)
    # The quotient times 2 to the power -$shift: find the $shift that gives
    # it 53 bits, or the most a subnormal has.
    $shift = 53 - [int][System.Math]::Floor($big::Log($numerator, 2) - $big::Log($denominator, 2))
    if ($shift -gt 1074) {
        $shift = 1074
    }
    while ($true) {
        if ($shift -ge 0) {
            $scaledNumerator = $numerator * $big::Pow(2, $shift)
            $scaledDenominator = $denominator
        } else {
            $scaledNumerator = $numerator
            $scaledDenominator = $denominator * $big::Pow(2, 0 - $shift)
        }
        $remainder = $big::Zero
        $quotient = $big::DivRem($scaledNumerator, $scaledDenominator, [ref]$remainder)
        if ($quotient -ge $top -and $shift -gt -2000) {
            $shift -= 1
        } elseif ($quotient -lt $bottom -and $shift -lt 1074) {
            $shift += 1
        } else {
            break
        }
    }
    $half = ($remainder * 2).CompareTo($scaledDenominator)
    if ($half -gt 0 -or ($half -eq 0 -and -not $quotient.IsEven)) {
        $quotient += 1
        if ($quotient -eq $top) {
            $quotient = $bottom
            $shift -= 1
        }
    }
    if (-$shift -gt 971) {
        return [double]::PositiveInfinity
    }
    return [double]$quotient * [System.Math]::Pow(2, 0 - $shift)
}

# The digits and decimal exponent of the shortest decimal that reads back as
# the positive double $Number, and of those the nearest, as Python's repr
# finds them: @('15', 2) for 150.0. Rounds the exact decimal expansion
# itself, because .NET Framework's ToString('E<n>') rounds twice.
function Get-ShortestDigit {
    param([double]$Number)

    $bits = [System.BitConverter]::DoubleToInt64Bits($Number)
    $binaryExponent = [int](($bits -shr 52) -band 0x7FF)
    $mantissa = [System.Numerics.BigInteger]($bits -band 0xFFFFFFFFFFFFF)
    if ($binaryExponent -eq 0) {
        $binaryExponent = 1
    } else {
        $mantissa += [System.Numerics.BigInteger]::Pow(2, 52)
    }
    $binaryExponent -= 1075
    # The value is $exact times 10 to the power $scale, exactly.
    if ($binaryExponent -ge 0) {
        $exact = ($mantissa * [System.Numerics.BigInteger]::Pow(2, $binaryExponent)).ToString()
        $scale = 0
    } else {
        $exact = ($mantissa * [System.Numerics.BigInteger]::Pow(5, 0 - $binaryExponent)).ToString()
        $scale = $binaryExponent
    }
    $exponent = $exact.Length - 1 + $scale
    $exact = $exact.TrimEnd('0')

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    for ($precision = 1; $precision -le 17; $precision++) {
        $digits = $exact
        $candidateExponent = $exponent
        if ($exact.Length -gt $precision) {
            $digits = $exact.Substring(0, $precision)
            $rest = $exact.Substring($precision)
            $last = [int][string]$digits[$precision - 1]
            $up = $rest[0] -gt [char]'5' -or ($rest[0] -ceq [char]'5' -and ($rest.Length -gt 1 -or $last % 2 -eq 1))
            if ($up) {
                $digits = ([System.Numerics.BigInteger]::Parse($digits) + 1).ToString()
                if ($digits.Length -gt $precision) {
                    $digits = $digits.Substring(0, $precision)
                    $candidateExponent += 1
                }
            }
        }
        $digits = $digits.TrimEnd('0')
        if ($digits -ceq '') {
            $digits = '0'
        }
        $candidate = '0.' + $digits + 'E' + ($candidateExponent + 1).ToString($invariant)
        if ((ConvertFrom-FloatText -Text $candidate) -eq $Number) {
            return , @($digits, $candidateExponent)
        }
    }
    throw 'No round-trip digits'
}

# A JSON number as Python's json.dumps writes it back after json.loads: an
# int keeps its digits, a float becomes repr(float).
function Format-JsonNumber {
    param([string]$Text, [bool]$IsFloat)

    if (-not $IsFloat) {
        # Python refuses to convert an int of more than 4300 digits.
        if ($Text.TrimStart('-').Length -gt 4300) {
            throw 'Integer too long'
        }
        if ($Text -ceq '-0') {
            return '0'
        }
        return $Text
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $number = ConvertFrom-FloatText -Text $Text
    if ([double]::IsNaN($number)) {
        return 'NaN'
    }
    if ([double]::IsPositiveInfinity($number)) {
        return 'Infinity'
    }
    if ([double]::IsNegativeInfinity($number)) {
        return '-Infinity'
    }
    if ($number -eq 0) {
        # From the text: .NET Framework parses -0.0 as 0.0.
        if ($Text.StartsWith('-', [System.StringComparison]::Ordinal)) {
            return '-0.0'
        }
        return '0.0'
    }

    $sign = ''
    if ($number -lt 0) {
        $sign = '-'
    }
    $shortest = Get-ShortestDigit -Number ([System.Math]::Abs($number))
    $digits = $shortest[0]
    $exponent = $shortest[1]

    if ($exponent -lt -4 -or $exponent -ge 16) {
        $mantissa = $digits.Substring(0, 1)
        if ($digits.Length -gt 1) {
            $mantissa += '.' + $digits.Substring(1)
        }
        $exponentSign = '+'
        if ($exponent -lt 0) {
            $exponentSign = '-'
        }
        return $sign + $mantissa + 'e' + $exponentSign + ([System.Math]::Abs($exponent)).ToString('00', $invariant)
    }
    if ($exponent -lt 0) {
        return $sign + '0.' + ('0' * (-$exponent - 1)) + $digits
    }
    $whole = $digits.PadRight($exponent + 1, '0')
    $fraction = $whole.Substring($exponent + 1)
    if ($fraction -ceq '') {
        $fraction = '0'
    }
    return $sign + $whole.Substring(0, $exponent + 1) + '.' + $fraction
}

# A JSON string literal as Python's json.dumps writes it. With -EnsureAscii
# (the default for json.dumps) everything outside space to ~ is escaped;
# without it (ensure_ascii=False) only control characters are.
function ConvertTo-JsonStringLiteral {
    param([string]$Text, [switch]$EnsureAscii)

    $escaped = $Text.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
    $escaped = $escaped.Replace([string][char]8, '\b').Replace([string][char]12, '\f')
    $others = '[\x00-\x1f]'
    if ($EnsureAscii) {
        $others = '[^\x20-\x7e]'
    }
    if ([regex]::IsMatch($escaped, $others)) {
        $hex = [System.Text.RegularExpressions.MatchEvaluator] {
            param($character)
            return '\u{0:x4}' -f [int][char]$character.Value
        }
        $escaped = [regex]::Replace($escaped, $others, $hex)
    }
    return '"' + $escaped + '"'
}

function Add-PythonJson {
    param([System.Text.StringBuilder]$Builder, $Value, [switch]$EnsureAscii)

    if ($null -eq $Value) {
        [void]$Builder.Append('null')
    } elseif ($Value -is [bool]) {
        if ($Value) {
            [void]$Builder.Append('true')
        } else {
            [void]$Builder.Append('false')
        }
    } elseif ($Value -is [string]) {
        [void]$Builder.Append((ConvertTo-JsonStringLiteral -Text $Value -EnsureAscii:$EnsureAscii))
    } elseif ($Value -is [System.Collections.Generic.Dictionary[string, object]]) {
        [void]$Builder.Append('{')
        $first = $true
        foreach ($key in $Value.Keys) {
            if (-not $first) {
                [void]$Builder.Append(', ')
            }
            $first = $false
            [void]$Builder.Append((ConvertTo-JsonStringLiteral -Text $key -EnsureAscii:$EnsureAscii)).Append(': ')
            Add-PythonJson -Builder $Builder -Value $Value[$key] -EnsureAscii:$EnsureAscii
        }
        [void]$Builder.Append('}')
    } elseif ($Value -is [System.Collections.Generic.List[object]]) {
        [void]$Builder.Append('[')
        for ($i = 0; $i -lt $Value.Count; $i++) {
            if ($i -gt 0) {
                [void]$Builder.Append(', ')
            }
            Add-PythonJson -Builder $Builder -Value $Value[$i] -EnsureAscii:$EnsureAscii
        }
        [void]$Builder.Append(']')
    } else {
        [void]$Builder.Append($Value.PythonJson)
    }
}

# A value from ConvertFrom-HookJson as Python's json.dumps writes it, with
# its default separators.
function ConvertTo-PythonJson {
    param($Value, [switch]$EnsureAscii)

    $builder = [System.Text.StringBuilder]::new()
    Add-PythonJson -Builder $builder -Value $Value -EnsureAscii:$EnsureAscii
    return $builder.ToString()
}

# The reference's as_object, as_list and as_str.
function Get-JsonObject {
    param($Value)

    if ($Value -is [System.Collections.Generic.Dictionary[string, object]]) {
        return , $Value
    }
    return , [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
}

function Get-JsonList {
    param($Value)

    if ($Value -is [System.Collections.Generic.List[object]]) {
        return , $Value
    }
    return , [System.Collections.Generic.List[object]]::new()
}

function Get-JsonString {
    param($Value)

    if ($Value -is [string]) {
        return $Value
    }
    return ''
}

# $Object[$Name], or $null when it isn't there.
function Get-JsonMember {
    param($Object, [string]$Name)

    $value = $null
    if ($Object -is [System.Collections.Generic.Dictionary[string, object]] -and $Object.TryGetValue($Name, [ref]$value)) {
        return , $value
    }
    return $null
}

# The words of a command, as Python's shlex.split splits it, or, when it
# can't (an unclosed quote or a trailing backslash), as str.split does.
function Split-CommandWord {
    param([string]$Command)

    try {
        return , (Split-ShellWord -Command $Command)
    } catch {
        $pattern = '[' + [regex]::Escape([string]::new((Get-PythonWhitespace))) + ']+'
        $words = [System.Collections.Generic.List[string]]::new()
        foreach ($word in [regex]::Split($Command, $pattern)) {
            if ($word.Length -gt 0) {
                $words.Add($word)
            }
        }
        return , $words.ToArray()
    }
}

# shlex.split(command) in POSIX mode: whitespace splits, quotes and
# backslashes are removed, and inside double quotes a backslash escapes only
# a backslash or a double quote. Throws where shlex raises ValueError.
function Split-ShellWord {
    param([string]$Command)

    $special = [char[]]@(' ', "`t", "`r", "`n", "'", '"', '\')
    $quoted = [char[]]@('"', '\')
    $words = [System.Collections.Generic.List[string]]::new()
    $word = [System.Text.StringBuilder]::new()
    $inWord = $false
    $length = $Command.Length
    $i = 0
    while ($i -lt $length) {
        $c = $Command[$i]
        if ($c -ceq ' ' -or $c -ceq "`t" -or $c -ceq "`r" -or $c -ceq "`n") {
            if ($inWord) {
                $words.Add($word.ToString())
                $word.Length = 0
                $inWord = $false
            }
            $i += 1
            continue
        }
        $inWord = $true
        if ($c -ceq "'") {
            $close = $Command.IndexOf([char]"'", $i + 1)
            if ($close -lt 0) {
                throw 'No closing quotation'
            }
            [void]$word.Append($Command, $i + 1, $close - $i - 1)
            $i = $close + 1
        } elseif ($c -ceq '"') {
            $i += 1
            while ($true) {
                $next = $Command.IndexOfAny($quoted, $i)
                if ($next -lt 0) {
                    throw 'No closing quotation'
                }
                [void]$word.Append($Command, $i, $next - $i)
                if ($Command[$next] -ceq '"') {
                    $i = $next + 1
                    break
                }
                if ($next + 1 -ge $length) {
                    throw 'No closing quotation'
                }
                $escaped = $Command[$next + 1]
                if ($escaped -cne '\' -and $escaped -cne '"') {
                    [void]$word.Append('\')
                }
                [void]$word.Append($escaped)
                $i = $next + 2
            }
        } elseif ($c -ceq '\') {
            if ($i + 1 -ge $length) {
                throw 'No escaped character'
            }
            [void]$word.Append($Command[$i + 1])
            $i += 2
        } else {
            $next = $Command.IndexOfAny($special, $i)
            if ($next -lt 0) {
                $next = $length
            }
            [void]$word.Append($Command, $i, $next - $i)
            $i = $next
        }
    }
    if ($inWord) {
        $words.Add($word.ToString())
    }
    return , $words.ToArray()
}

# os.path.join($Base, os.path.expanduser($Path)). On Windows it also turns
# Git Bash's /c/... and /tmp/... into Windows paths.
function Resolve-ShellPath {
    param([string]$Base, [string]$Path)

    $onWindows = Test-WindowsHost
    $separators = [char[]]@('/')
    if ($onWindows) {
        $separators = [char[]]@('/', '\')
    }

    if ($Path.StartsWith('~', [System.StringComparison]::Ordinal)) {
        $end = $Path.IndexOfAny($separators, 1)
        if ($end -lt 0) {
            $end = $Path.Length
        }
        $userHome = $env:HOME
        if (-not $userHome) {
            $userHome = $env:USERPROFILE
        }
        # ~user is left alone.
        if ($end -eq 1 -and $userHome) {
            $Path = $userHome.TrimEnd($separators) + $Path.Substring(1)
            if ($Path -ceq '') {
                $Path = [string]$separators[0]
            }
        }
    }

    if ($onWindows) {
        $drive = [regex]::Match($Path, '\A/([A-Za-z])(/.*)?\z', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($drive.Success) {
            $rest = $drive.Groups[2].Value
            if ($rest -ceq '') {
                $rest = '/'
            }
            $Path = $drive.Groups[1].Value + ':' + $rest
        } elseif ($Path -ceq '/tmp' -or $Path.StartsWith('/tmp/', [System.StringComparison]::Ordinal)) {
            $temp = $env:TEMP
            if (-not $temp) {
                $temp = [System.IO.Path]::GetTempPath()
            }
            $Path = $temp.TrimEnd($separators) + $Path.Substring(4)
        }

        if ([regex]::IsMatch($Path, '\A(?:[A-Za-z]:|[\\/]{2})')) {
            return $Path
        }
        if ([regex]::IsMatch($Path, '\A[\\/]')) {
            $root = [regex]::Match($Base, '\A[A-Za-z]:')
            if ($root.Success) {
                return $root.Value + $Path
            }
            return $Path
        }
        if ($Base -ceq '' -or $Base.EndsWith('\', [System.StringComparison]::Ordinal) -or $Base.EndsWith('/', [System.StringComparison]::Ordinal)) {
            return $Base + $Path
        }
        return $Base + '\' + $Path
    }

    if ($Path.StartsWith('/', [System.StringComparison]::Ordinal)) {
        return $Path
    }
    if ($Base -ceq '' -or $Base.EndsWith('/', [System.StringComparison]::Ordinal)) {
        return $Base + $Path
    }
    return $Base + '/' + $Path
}

# The directory after the first git -C, or $Cwd.
function Get-GitDirectory {
    param([string[]]$Word, [string]$Cwd)

    for ($i = 0; $i -lt $Word.Count - 1; $i++) {
        if ($Word[$i] -ceq '-C') {
            return Resolve-ShellPath -Base $Cwd -Path $Word[$i + 1]
        }
    }
    return $Cwd
}

# The text of a message file, read as Python's open(errors="replace").read()
# reads it, or $null when it isn't a file of at most 1,000,000 bytes.
function Read-MessageFile {
    param([string]$Path)

    $info = [System.IO.FileInfo]::new($Path)
    if (-not $info.Exists) {
        return $null
    }
    # Off Windows, an empty file has no link, and this skips FIFOs and
    # devices that would block, which Python's os.path.isfile refuses.
    if (-not (Test-WindowsHost) -and $info.Length -eq 0) {
        return $null
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -gt 1000000) {
            return $null
        }
        $bytes = [byte[]]::new($stream.Length)
        $read = 0
        while ($read -lt $bytes.Length) {
            $count = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($count -le 0) {
                break
            }
            $read += $count
        }
    } finally {
        $stream.Dispose()
    }
    $text = [System.Text.UTF8Encoding]::new($false, $false).GetString($bytes, 0, $read)
    return $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

# The text of every message or body file the command passes.
function Get-MessageFileText {
    param([string[]]$Word, [string]$Cwd)

    $flags = Get-MessageFileFlag
    $paths = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Word.Count; $i++) {
        $current = $Word[$i]
        $equals = $current.IndexOf([char]'=')
        if ($flags.Contains($current) -and $i + 1 -lt $Word.Count) {
            $paths.Add($Word[$i + 1])
        } elseif ($equals -ge 0 -and $flags.Contains($current.Substring(0, $equals))) {
            $paths.Add($current.Substring($equals + 1))
        }
    }
    $base = Get-GitDirectory -Word $Word -Cwd $Cwd
    $texts = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        # gh api -F takes key=value fields, not files.
        if ($path -ceq '-' -or $path.IndexOf([char]'=') -ge 0) {
            continue
        }
        try {
            $text = Read-MessageFile -Path (Resolve-ShellPath -Base $base -Path $path)
            if ($null -ne $text) {
                $texts.Add($text)
            }
        } catch {
            # Unreadable, or not a valid path here: skip it, as the
            # reference skips an OSError.
            $null = $_
        }
    }
    return , $texts
}

# git, found on PATH. On Windows, CreateProcess would look in the current
# directory first, so search PATH alone, as execvp does.
function Get-GitExecutable {
    if (-not (Test-WindowsHost)) {
        return 'git'
    }
    foreach ($directory in ([string]$env:PATH).Split([char]';')) {
        $directory = $directory.Trim().Trim([char]'"')
        if ($directory -ceq '') {
            continue
        }
        try {
            $candidate = [System.IO.Path]::Combine($directory, 'git.exe')
            if ([System.IO.File]::Exists($candidate)) {
                return $candidate
            }
        } catch {
            $null = $_
        }
    }
    throw 'git is not on PATH'
}

# Arguments quoted for ProcessStartInfo.Arguments, which splits them the way
# the Windows C runtime does.
function ConvertTo-ProcessArgumentString {
    param([string[]]$Argument)

    $quoted = foreach ($item in $Argument) {
        if ($item.Length -gt 0 -and -not [regex]::IsMatch($item, '[\s"]')) {
            $item
        } else {
            '"' + [regex]::Replace([regex]::Replace($item, '(\\*)"', '$1$1\"'), '(\\+)\z', '$1$1') + '"'
        }
    }
    return $quoted -join ' '
}

# git log's output for the commits on HEAD that no remote has, or $null when
# git fails. Throws when it takes more than 5 seconds, as the reference's
# subprocess.run does, so the hook fails open.
function Invoke-GitLog {
    param([string]$Directory)

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Get-GitExecutable
    $info.Arguments = ConvertTo-ProcessArgumentString -Argument @('-C', $Directory, 'log', 'HEAD', '--not', '--remotes', '--format=%h%x00%B%x01')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) {
            try {
                $process.Kill()
            } catch {
                $null = $_
            }
            throw 'git log timed out'
        }
        $process.WaitForExit()
        $null = $errors.Result
        if ($process.ExitCode -ne 0) {
            return $null
        }
        return $output.Result
    } finally {
        $process.Dispose()
    }
}

# Each commit on HEAD that no remote has yet, as @(short hash, message).
function Get-UnpushedMessage {
    param([string[]]$Word, [string]$Cwd)

    $commits = [System.Collections.Generic.List[object]]::new()
    $output = Invoke-GitLog -Directory (Get-GitDirectory -Word $Word -Cwd $Cwd)
    if ($null -eq $output) {
        return , $commits
    }
    $output = $output.Replace("`r`n", "`n").Replace("`r", "`n")
    foreach ($entry in $output.Split([char]1)) {
        $entry = $entry.Trim([char]10)
        $split = $entry.IndexOf([char]0)
        if ($split -lt 0) {
            $sha = $entry
            $body = ''
        } else {
            $sha = $entry.Substring(0, $split)
            $body = $entry.Substring($split + 1)
        }
        if ($sha -cne '') {
            $commits.Add(@($sha, $body))
        }
    }
    return , $commits
}

function Get-BashProblem {
    param([string]$Command, [string]$Cwd)

    $hit = Find-SessionLink -Text $Command
    if ($hit) {
        return 'The command contains ' + $hit[0] + ': ' + $hit[1]
    }
    # A word can be git or gh only if the command holds it once quotes and
    # backslashes are gone: skip splitting the rest.
    $bare = $Command.Replace("'", '').Replace('"', '').Replace('\', '')
    if ($bare.IndexOf('git', [System.StringComparison]::Ordinal) -lt 0 -and $bare.IndexOf('gh', [System.StringComparison]::Ordinal) -lt 0) {
        return $null
    }
    $words = Split-CommandWord -Command $Command
    $hasGit = $words -ccontains 'git'
    if (-not $hasGit -and -not ($words -ccontains 'gh')) {
        return $null
    }
    foreach ($text in (Get-MessageFileText -Word $words -Cwd $Cwd)) {
        $hit = Find-SessionLink -Text $text
        if ($hit) {
            return 'A message file passed to the command contains ' + $hit[0] + ': ' + $hit[1]
        }
    }
    if ($hasGit -and $words -ccontains 'push') {
        foreach ($commit in (Get-UnpushedMessage -Word $words -Cwd $Cwd)) {
            $hit = Find-SessionLink -Text $commit[1]
            if ($hit) {
                return 'Unpushed commit ' + $commit[0] + ' has ' + $hit[0] + ' in its message: ' + $hit[1] + '. Reword it before you push'
            }
        }
    }
    return $null
}

function Get-WrittenText {
    param([string]$Tool, $ToolInput)

    if ($Tool -ceq 'MultiEdit') {
        $parts = foreach ($edit in (Get-JsonList -Value (Get-JsonMember -Object $ToolInput -Name 'edits'))) {
            Get-JsonString -Value (Get-JsonMember -Object (Get-JsonObject -Value $edit) -Name 'new_string')
        }
        return [string]::Join("`n", [string[]]@($parts))
    }
    $field = ''
    switch -CaseSensitive ($Tool) {
        'Write' { $field = 'content' }
        'Edit' { $field = 'new_string' }
        'NotebookEdit' { $field = 'new_source' }
    }
    return Get-JsonString -Value (Get-JsonMember -Object $ToolInput -Name $field)
}

# What's wrong with the call, or $null.
function Get-HookProblem {
    param($Payload)

    $eventName = Get-JsonString -Value (Get-JsonMember -Object $Payload -Name 'hook_event_name')
    if ($eventName -cne '' -and $eventName -cne 'PreToolUse') {
        return $null
    }
    $tool = Get-JsonString -Value (Get-JsonMember -Object $Payload -Name 'tool_name')
    $toolInput = Get-JsonObject -Value (Get-JsonMember -Object $Payload -Name 'tool_input')
    $cwd = Get-JsonString -Value (Get-JsonMember -Object $Payload -Name 'cwd')
    if ($cwd -ceq '') {
        $cwd = [System.IO.Directory]::GetCurrentDirectory()
    }
    if ($tool -ceq 'Bash' -or $tool -ceq 'Monitor') {
        return Get-BashProblem -Command (Get-JsonString -Value (Get-JsonMember -Object $toolInput -Name 'command')) -Cwd $cwd
    }
    if ($tool -ceq 'Write' -or $tool -ceq 'Edit' -or $tool -ceq 'NotebookEdit' -or $tool -ceq 'MultiEdit') {
        $hit = Find-SessionLink -Text (Get-WrittenText -Tool $tool -ToolInput $toolInput)
        if ($hit) {
            return 'The text being written contains ' + $hit[0] + ': ' + $hit[1]
        }
        return $null
    }
    if ($tool.StartsWith('mcp__', [System.StringComparison]::Ordinal)) {
        $hit = Find-SessionLink -Text (ConvertTo-PythonJson -Value $toolInput)
        if ($hit) {
            return 'The tool input contains ' + $hit[0] + ': ' + $hit[1]
        }
    }
    return $null
}

# The reply JSON for a parsed event, or $null when the hook decides nothing.
function Get-HookReply {
    param($Payload)

    $problem = Get-HookProblem -Payload (Get-JsonObject -Value $Payload)
    if (-not $problem) {
        return $null
    }
    $reason = -join @(
        'Blocked by the no-session-links hook. ', $problem, '. ',
        'The user never wants Claude Code session links, Claude-Session trailers or claude.ai ',
        'links in commits, pull requests, comments, issues, releases or files, even when Claude ',
        'Code''s attribution guidance asks for them. Remove the link and try again. Keep the ',
        'Co-Authored-By footer. Don''t work around this hook.'
    )
    $output = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $output['hookEventName'] = 'PreToolUse'
    $output['permissionDecision'] = 'deny'
    $output['permissionDecisionReason'] = $reason
    $reply = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $reply['hookSpecificOutput'] = $output
    return ConvertTo-PythonJson -Value $reply -EnsureAscii
}

# The hook on the text of one event: the reply to print, or '' for none.
# Anything but a JSON object decides nothing, and any error prints nothing.
function Invoke-NoSessionLinksHook {
    param([string]$InputText)

    try {
        $reply = Get-HookReply -Payload (ConvertFrom-HookJson -Text $InputText)
        if ($reply) {
            return $reply
        }
    } catch {
        # A broken hook must never break Claude Code.
        $null = $_
    }
    return ''
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        $buffer = [System.IO.MemoryStream]::new()
        [System.Console]::OpenStandardInput().CopyTo($buffer)
        # Strict, as Python's stdin is: invalid UTF-8 fails open.
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($buffer.ToArray())
        $reply = Invoke-NoSessionLinksHook -InputText $text
        if ($reply) {
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($reply)
            $stdout = [System.Console]::OpenStandardOutput()
            $stdout.Write($bytes, 0, $bytes.Length)
            $stdout.Flush()
        }
    } catch {
        $null = $_
    }
    exit 0
}
