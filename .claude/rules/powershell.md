---
paths:
  - "**/*.ps1"
  - "**/*.psd1"
---

# PowerShell

The Windows installer (`src/install.ps1` and each module's `bootstrap.ps1`),
the pwsh module's profile templates and the claude module's Windows hooks.

- PowerShell 7 first, but everything must also run on Windows PowerShell 5.1:
  no `??`, `?.`, ternaries, `&&`/`||` between pipelines, `-Parallel`, or
  `ConvertFrom-Json -AsHashtable`/`-Depth`. Guard a newer parameter at
  runtime and pass it by splatting, as `ConvertFrom-ClaudeJson` does with
  `-DateKind`.
- ASCII source only: 5.1 reads a file without a BOM as ANSI. Write any other
  character as `[char]0xNNNN`.
- Lint with PSScriptAnalyzer and `PSScriptAnalyzerSettings.psd1` (CI and the
  VS Code extension use it): same-line braces, 4-space indent, approved
  `Verb-Noun` names, no aliases. The PostToolUse hook parses each edited
  file, and lints it when the module is installed.
- Functions return `$true` or `$false`, and nothing else reaches the output
  stream: assign or `$null =` every call whose output you don't return.
  Return an array as `return , $x`, and never wrap a call in `@(...)` to get
  one back, because that nests it. Don't assign a value that may be an array
  from an `if` statement (`$x = if (...) { $a } else { $b }`): its output is
  unrolled, so a one-item array becomes its item.
- Use .NET (`[IO.File]`) rather than `Get-FileHash` and other script-module
  commands in the installer: Windows PowerShell started from pwsh inherits
  pwsh's `PSModulePath` and can't load them.

## The installer

- Log with `Write-DotfilesLog <level> "message"`, defined in
  `src/install.ps1` with `Initialize-Directory` and `Install-File`. It
  mirrors `install.sh`: same levels, file and JSON lines. Paths in messages
  are wrapped as `<path>`.
- A module is `src/modules/<name>/bootstrap.ps1` defining `Invoke-Bootstrap`,
  which returns `$true` or `$false`. `install.ps1` runs it only when `<name>`
  is an application on `PATH`, dot-sourced in a scope of its own, so names
  don't leak between modules. Resolve the module's files from
  `$PSScriptRoot`.
- Collect failures in an `$errors`/`$failed` flag rather than stopping, and
  catch exceptions with `-ErrorAction Stop` inside `try` where a cmdlet can
  fail.
- Install files with `Install-File`, so a link or an unchanged file is left
  alone.

## Installed hooks (`src/modules/claude/windows/hooks/`)

- Each is the twin of a POSIX hook in `templates/hooks/` and must decide the
  same way: a fix to one is a fix to both, each with a test case.
- Self-contained, and they never call the installer's helpers. Read stdin as
  UTF-8 bytes, write only the reply, as UTF-8 without a BOM, and fail open:
  any error exits 0 with no output.
- Tests are Pester 5 files beside the module's pytest tests
  (`src/modules/claude/tests/*.Tests.ps1`). CI runs them on Windows under
  both pwsh and Windows PowerShell. Each suppresses `PSUseCompatibleCommands`
  at the top, because the compatibility profiles only know the Pester 3 that
  ships with Windows.
