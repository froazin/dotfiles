#!/usr/bin/env python3
"""Claude Code hook: the commit-signing guard.

Keeps agents from bypassing git commit signing, and makes them stop and
report when signing fails, for example when 1Password's Windows Hello prompt
times out because the user is away.

  PreToolUse            deny signing bypasses; while the session is locked,
                        deny git commands that sign
  PostToolUse(Failure)  on a signing failure or hang, lock the session and
                        tell the model to stop and report
  UserPromptSubmit      unlock: the user is back

Commands are lexed like a shell (quotes, heredocs, $(...), sh -c, ...), so the
rules see git's real arguments and commit messages stay data. It is a guard
rail against an agent's habits, not a security boundary: scripts on disk,
other interpreters or other git clients can still get past it.

Standard library only. Any internal error fails open: nothing is printed.
"""

import contextlib
import json
import os
import re
import stat
import subprocess
import sys
from typing import Literal, cast

# What a command in a script amounts to, for the hang heuristics.
type Kind = Literal["quick", "signing", "other", "slow-git"]
# Variables a script set (None: unset), as far as the guard can tell.
type Env = dict[str, str | None]
type Reply = dict[str, object]


def as_object(value: object) -> dict[str, object]:
    """A JSON object from the hook input, or an empty one."""
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def as_str(value: object) -> str:
    return value if isinstance(value, str) else ""


# ---------------------------------------------------------------------------
# Shell lexer
# ---------------------------------------------------------------------------

OPERATORS = ("&&", "||", ";;", "|&", ";", "&", "|", "(", ")", "\n")
REDIRECTS = ("&>>", "<<<", "<<-", "<<", ">>", "&>", ">|", ">&", "<&", "<>", "<", ">")
WRITE_REDIRECTS = {">", ">>", ">|", "&>", "&>>", "<>"}
WORD_END = " \t\r\n;&|()<>"
MAX_DEPTH = 8


class Word:
    """A shell word: its text with quoting removed, the source of any command
    substitutions in it (the text keeps them verbatim), whether any of it was
    quoted, and, for a heredoc delimiter, the heredoc's body."""

    def __init__(self) -> None:
        self.text = ""
        self.subs: list[str] = []
        self.quoted = False
        self.body: str | None = None


class Command:
    """A simple command: words, redirections, the operator after it, and how
    many ( subshells deep it is."""

    def __init__(self, depth: int = 0) -> None:
        self.words: list[Word] = []
        self.redirects: list[tuple[str, Word]] = []
        self.op: str | None = None
        self.depth = depth


def _match(s: str, i: int, options: tuple[str, ...]) -> str | None:
    for option in options:
        if s.startswith(option, i):
            return option
    return None


def lex(s: str, i: int = 0, closing: bool = False) -> tuple[list[Command], int]:
    """Split shell source into simple commands. With closing=True, stop after
    the ")" that ends a $( ... ) and return the index after it."""
    commands: list[Command] = []
    cur = Command()
    heredocs: list[tuple[Word, bool]] = []
    depth = 0
    n = len(s)

    def finish(op: str | None) -> None:
        nonlocal cur
        cur.op = op
        if cur.words or cur.redirects:
            commands.append(cur)
        cur = Command(depth)

    while i < n:
        c = s[i]
        if c == "\\" and s.startswith("\\\n", i):
            i += 2
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "#":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "\n":
            finish("\n")
            i += 1
            for target, strip_tabs in heredocs:
                target.body, i = _read_heredoc(s, i, target.text, strip_tabs)
            heredocs = []
            continue
        if s.startswith("<(", i) or s.startswith(">(", i):
            word = Word()
            i = _read_substitution(s, i + 1, word, prefix=s[i])
            cur.words.append(word)
            continue
        op = _match(s, i, REDIRECTS)
        if op:
            i += len(op)
            while i < n and s[i] in " \t":
                i += 1
            target, i = read_word(s, i)
            if op in ("<<", "<<-"):
                heredocs.append((target, op == "<<-"))
            cur.redirects.append((op, target))
            continue
        op = _match(s, i, OPERATORS)
        if op:
            i += len(op)
            if op == ")":
                if closing and depth == 0:
                    finish(op)
                    return commands, i
                depth -= 1
            elif op == "(":
                depth += 1
            finish(op)
            continue
        word, i = read_word(s, i)
        # "2>" and friends: the digits name a file descriptor, not a word.
        if i < n and s[i] in "<>" and word.text.isdigit() and not word.subs:
            continue
        cur.words.append(word)
    finish(None)
    return commands, i


def _read_heredoc(s: str, i: int, delimiter: str, strip_tabs: bool) -> tuple[str, int]:
    """Return a heredoc's body and the index after its delimiter line."""
    n = len(s)
    lines: list[str] = []
    while i < n:
        j = s.find("\n", i)
        j = n if j < 0 else j
        line = s[i:j].lstrip("\t") if strip_tabs else s[i:j]
        if line == delimiter:
            return "\n".join(lines), j + 1
        lines.append(line)
        i = j + 1
    return "\n".join(lines), n


def read_word(s: str, i: int) -> tuple[Word, int]:
    word = Word()
    n = len(s)
    while i < n:
        c = s[i]
        if c in WORD_END:
            break
        if c == "\\":
            if i + 1 < n and s[i + 1] != "\n":
                word.text += s[i + 1]
                word.quoted = True
            i += 2
        elif c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            word.text += s[i + 1 : j]
            word.quoted = True
            i = j + 1
        elif c == '"':
            word.quoted = True
            i = _read_double(s, i + 1, word)
        elif s.startswith("$'", i):
            word.quoted = True
            i = _read_ansi_c(s, i + 2, word)
        elif c in "$`":
            i = _read_expansion(s, i, word)
        else:
            word.text += c
            i += 1
    return word, i


def _read_double(s: str, i: int, word: Word) -> int:
    n = len(s)
    while i < n:
        c = s[i]
        if c == '"':
            return i + 1
        if c == "\\" and i + 1 < n:
            if s[i + 1] == "\n":
                i += 2
                continue
            if s[i + 1] in '$`"\\':
                word.text += s[i + 1]
                i += 2
                continue
        if c in "$`":
            i = _read_expansion(s, i, word)
            continue
        word.text += c
        i += 1
    return n


ANSI_C = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "\\": "\\",
    "'": "'",
    '"': '"',
    "?": "?",
    "e": "\x1b",
    "E": "\x1b",
    "a": "\a",
    "b": "\b",
    "f": "\f",
    "v": "\v",
}
ANSI_C_NUMERIC = re.compile(r"x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|[0-7]{1,3}|c.")


def _read_ansi_c(s: str, i: int, word: Word) -> int:
    """Decode $'...' as bash does."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "'":
            return i + 1
        if c == "\\" and i + 1 < n:
            numeric = ANSI_C_NUMERIC.match(s, i + 1)
            if numeric:
                code = numeric.group()
                if code[0] == "c":
                    word.text += chr(ord(code[1]) & 0x1F)
                elif code[0] in "xuU":
                    word.text += chr(min(int(code[1:], 16), 0x10FFFF))
                else:
                    word.text += chr(int(code, 8) & 0xFF)
                i = numeric.end()
                continue
            word.text += ANSI_C.get(s[i + 1], "\\" + s[i + 1])
            i += 2
            continue
        word.text += c
        i += 1
    return n


def _read_substitution(s: str, i: int, word: Word, prefix: str = "$") -> int:
    """s[i] is the "(" of $( or <( or >(; record the inner source."""
    _, end = lex(s, i + 1, closing=True)
    inner = s[i + 1 : end - 1] if s[end - 1 : end] == ")" else s[i + 1 : end]
    word.subs.append(inner)
    word.text += prefix + s[i:end]
    return end


def _read_expansion(s: str, i: int, word: Word) -> int:
    n = len(s)
    if s.startswith("$((", i):
        depth = 0
        j = i + 1
        while j < n:
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        word.text += s[i:j]
        return j
    if s.startswith("$(", i):
        return _read_substitution(s, i + 1, word)
    if s.startswith("${", i):
        depth = 0
        j = i + 1
        while j < n:
            if s[j] == "{":
                depth += 1
            elif s[j] == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        word.text += s[i:j]
        return j
    if s[i] == "`":
        j = i + 1
        inner = ""
        while j < n and s[j] != "`":
            if s[j] == "\\" and j + 1 < n:
                inner += s[j + 1]
                j += 2
                continue
            inner += s[j]
            j += 1
        word.subs.append(inner)
        word.text += s[i : j + 1]
        return j + 1
    word.text += "$"
    return i + 1


# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
GIT_CONFIG_ENV = re.compile(r"^GIT_CONFIG_(COUNT|KEY_\d+|VALUE_\d+|PARAMETERS|GLOBAL|SYSTEM)$")
NO_GPG_SIGN = re.compile(r"^--no-g(p(g(-(s(i(gn?)?)?)?)?)?)?$")
NO_SIGN = re.compile(r"^--no-si(gn?)?$")
SIGNING_TEXT = re.compile(r"gpgsign|signingkey|\[\s*(commit|tag|gpg|include)|\binclude|\bgpg\.", re.I)
BYPASS_TEXT = re.compile(r"--no-g|--no-si|gpgsign|signingkey|\bgpg\.", re.I)
TRUE_INT = re.compile(r"^[+-]?\d+[kmgKMG]?$")

GPGSIGN_KEYS = {"commit.gpgsign", "tag.gpgsign"}
SIGNING_KEYS = {
    "gpg.format",
    "gpg.program",
    "gpg.ssh.program",
    "gpg.ssh.defaultkeycommand",
    "gpg.openpgp.program",
    "gpg.x509.program",
    "user.signingkey",
}
SIGNING_SECTIONS = {"commit", "tag", "gpg", "user", "include", "includeif"}

# Subcommands that create commits or tags, and accept --no-gpg-sign.
COMMIT_SUBS = {"commit", "merge", "rebase", "cherry-pick", "revert", "am", "pull", "commit-tree"}
# Modes of those that never create a commit.
NO_COMMIT_FLAGS = {"--abort", "--quit", "--show-current-patch", "--edit-todo"}
TAG_READ_FLAGS = {
    "-l",
    "--list",
    "-d",
    "--delete",
    "-v",
    "--verify",
    "--contains",
    "--no-contains",
    "--points-at",
    "--merged",
    "--no-merged",
}
UNSIGNED_PLUMBING = {"mktag", "fast-import", "filter-branch", "filter-repo", "replay"}

# git's global options that take a separate value.
GIT_VALUE_OPTS = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--super-prefix",
    "--config-env",
    "--list-cmds",
    "--attr-source",
}
# git config long options: (takes a value, action it implies).
CONFIG_OPTS: dict[str, tuple[bool, str | None]] = {
    "global": (False, None),
    "system": (False, None),
    "local": (False, None),
    "worktree": (False, None),
    "file": (True, None),
    "blob": (True, None),
    "get": (False, "get"),
    "get-all": (False, "get"),
    "get-regexp": (False, "get"),
    "get-urlmatch": (False, "get"),
    "get-color": (False, "get"),
    "get-colorbool": (False, "get"),
    "list": (False, "get"),
    "replace-all": (False, "set"),
    "add": (False, "set"),
    "unset": (False, "unset"),
    "unset-all": (False, "unset"),
    "rename-section": (False, "rename"),
    "remove-section": (False, "remove"),
    "edit": (False, "edit"),
    "type": (True, None),
    "bool": (False, None),
    "int": (False, None),
    "bool-or-int": (False, None),
    "path": (False, None),
    "expiry-date": (False, None),
    "no-type": (False, None),
    "null": (False, None),
    "name-only": (False, None),
    "show-origin": (False, None),
    "show-scope": (False, None),
    "includes": (False, None),
    "no-includes": (False, None),
    "default": (True, None),
    "comment": (True, None),
    "fixed-value": (False, None),
    "value": (True, None),
    "url": (True, None),
    "all": (False, None),
    "regexp": (False, None),
}
CONFIG_SUBCOMMANDS = {
    "get": "get",
    "list": "get",
    "get-color": "get",
    "get-colorbool": "get",
    "set": "set",
    "unset": "unset",
    "edit": "edit",
    "rename-section": "rename",
    "remove-section": "remove",
}

SUDO_VALUE_OPTS = {
    "-u",
    "-g",
    "-C",
    "-D",
    "-h",
    "-p",
    "-r",
    "-t",
    "-U",
    "-T",
    "--user",
    "--group",
    "--chdir",
    "--host",
    "--prompt",
    "--role",
    "--type",
    "--other-user",
    "--command-timeout",
}
XARGS_VALUE_OPTS = {
    "-a",
    "-d",
    "-E",
    "-I",
    "-L",
    "-n",
    "-P",
    "-s",
    "--arg-file",
    "--delimiter",
    "--eof",
    "--replace",
    "--max-lines",
    "--max-args",
    "--max-procs",
    "--max-chars",
    "--process-slot-var",
}
WRAPPER_VALUE_OPTS: dict[str, set[str]] = {
    "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "-P", "-u", "--class", "--classdata"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "stdbuf": {"-i", "-o", "-e"},
}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "mksh", "ash"}
# Shell options that take a value, before -c: bash -o pipefail -c '...'.
SHELL_VALUE_OPTS = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}"}
# $(which git), `command -v git`: the command name is git.
GIT_LOOKUP = re.compile(r"^(\$\(|`)\s*(which|command\s+-v|type\s+-[pP])\s+git\s*(\)|`)$")
SIMPLE_VARIABLE = re.compile(r"^\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))$")
VARIABLE = re.compile(r"\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
# Variables whose expansion the path checks handle themselves.
PATH_VARIABLES = {"HOME", "XDG_CONFIG_HOME", "CLAUDE_CONFIG_DIR", "XDG_RUNTIME_DIR"}
# Commands whose output, piped or fed to a shell, is the shell's script.
PRINTERS = {"echo", "printf", "cat"}
# Commands that remove or lock down whole directories.
DESTRUCTIVE = {"rm", "unlink", "shred", "mv", "chmod", "chown", "chgrp", "chattr"}
# Builtin git commands; anything else may be an alias.
GIT_BUILTINS = set(
    [
        "add",
        "am",
        "annotate",
        "apply",
        "archive",
        "bisect",
        "blame",
        "branch",
        "bundle",
        "cat-file",
        "check-attr",
        "check-ignore",
        "check-mailmap",
        "check-ref-format",
        "checkout",
        "checkout-index",
        "cherry",
        "cherry-pick",
        "citool",
        "clean",
        "clone",
        "column",
        "commit",
        "commit-graph",
        "commit-tree",
        "config",
        "count-objects",
        "credential",
        "describe",
        "diff",
        "diff-files",
        "diff-index",
        "diff-tree",
        "difftool",
        "fast-export",
        "fast-import",
        "fetch",
        "fetch-pack",
        "filter-branch",
        "filter-repo",
        "for-each-ref",
        "for-each-repo",
        "format-patch",
        "fsck",
        "gc",
        "get-tar-commit-id",
        "grep",
        "gui",
        "hash-object",
        "help",
        "index-pack",
        "init",
        "instaweb",
        "interpret-trailers",
        "lfs",
        "log",
        "ls-files",
        "ls-remote",
        "ls-tree",
        "mailinfo",
        "mailsplit",
        "maintenance",
        "merge",
        "merge-base",
        "merge-file",
        "merge-tree",
        "mergetool",
        "mktag",
        "mktree",
        "multi-pack-index",
        "mv",
        "name-rev",
        "notes",
        "pack-objects",
        "pack-refs",
        "patch-id",
        "prune",
        "pull",
        "push",
        "range-diff",
        "read-tree",
        "rebase",
        "reflog",
        "remote",
        "repack",
        "replace",
        "replay",
        "request-pull",
        "rerere",
        "reset",
        "restore",
        "rev-list",
        "rev-parse",
        "revert",
        "rm",
        "send-email",
        "shortlog",
        "show",
        "show-branch",
        "show-ref",
        "sparse-checkout",
        "stash",
        "status",
        "stripspace",
        "submodule",
        "switch",
        "symbolic-ref",
        "tag",
        "unpack-file",
        "unpack-objects",
        "update-index",
        "update-ref",
        "var",
        "verify-commit",
        "verify-pack",
        "verify-tag",
        "version",
        "whatchanged",
        "worktree",
        "write-tree",
    ]
)
# Subcommands that only read: signing overrides there can't create commits.
READ_ONLY_GIT = {
    "log",
    "show",
    "verify-commit",
    "verify-tag",
    "status",
    "diff",
    "cat-file",
    "rev-parse",
    "blame",
    "grep",
    "ls-files",
    "describe",
    "shortlog",
    "reflog",
    "show-ref",
    "for-each-ref",
}
# Commands that finish quickly, so a timeout can't be theirs.
QUICK_COMMANDS = {
    "cd",
    "echo",
    "printf",
    "true",
    "false",
    ":",
    "test",
    "[",
    "ls",
    "cat",
    "pwd",
    "mkdir",
    "touch",
    "cp",
    "mv",
    "rm",
    "export",
    "unset",
    "head",
    "tail",
    "wc",
    "grep",
    "rg",
    "sed",
    "awk",
    "sort",
    "uniq",
    "basename",
    "dirname",
    "realpath",
}
# git subcommands that may legitimately be slow (the network).
SLOW_GIT = {"push", "pull", "fetch", "clone", "ls-remote", "submodule", "lfs", "gc", "fsck"}


def truthy(value: str) -> bool:
    value = value.strip().lower()
    if value in ("true", "yes", "on"):
        return True
    if TRUE_INT.match(value):
        number = int(re.sub(r"[kmgKMG]$", "", value))
        return number != 0
    return False


def signing_override(key: str, value: str | None) -> str | None:
    """Why setting key to value (None: unknown) changes signing, or None."""
    key = key.lower()
    if key in GPGSIGN_KEYS:
        return None if value is not None and truthy(value) else key + " override"
    if key in SIGNING_KEYS or key == "include.path" or key.startswith("includeif."):
        return key + " override"
    if key.startswith("alias.") and (value is None or BYPASS_TEXT.search(value)):
        return "alias that changes signing"
    return None


def resolve_option(name: str, options: dict[str, tuple[bool, str | None]]) -> str | None:
    """git accepts any unambiguous prefix of a long option."""
    if name in options:
        return name
    candidates = [o for o in options if o.startswith(name)]
    if candidates and len({options[c][1] for c in candidates}) == 1:
        return candidates[0]
    return None


def skip_options(words: list[str], value_opts: set[str]) -> list[str]:
    """Drop a wrapper's options (and their values) up to its command."""
    i = 0
    while i < len(words):
        word = words[i]
        if word == "--":
            return words[i + 1 :]
        if not word.startswith("-") or word == "-":
            break
        i += 2 if word in value_opts else 1
    return words[i:]


class State:
    """What earlier commands in the same script changed."""

    def __init__(self, cwd: str, env: Env | None = None, aliases: dict[str, str] | None = None) -> None:
        self.cwd = cwd
        self.env: Env = dict(env or {})
        # git aliases defined earlier in the script with git config.
        self.aliases: dict[str, str] = dict(aliases or {})

    def copy(self) -> State:
        return State(self.cwd, self.env, self.aliases)


class Guard:
    def __init__(self, event: dict[str, object]) -> None:
        self.home = os.environ.get("HOME", "").rstrip("/")
        self.xdg = (os.environ.get("XDG_CONFIG_HOME") or self.home + "/.config").rstrip("/")
        self.claude_dir = (os.environ.get("CLAUDE_CONFIG_DIR") or self.home + "/.claude").rstrip("/")
        self.runtime = (os.environ.get("XDG_RUNTIME_DIR") or "").rstrip("/")
        cwd = event.get("cwd")
        self.cwd = cwd if isinstance(cwd, str) and cwd.startswith("/") else (os.getcwd() if os.path.isdir(".") else "/")
        self.locked = False
        self.bypasses: list[str] = []
        self.signing: list[str] = []
        self.kinds: list[Kind] = []
        # A signing command run under timeout(1): exit 124 means it hung.
        self.under_timeout = False

    # -- paths -------------------------------------------------------------

    def _value(self, name: str, real: str, env: Env | None) -> str | None:
        """The value of a path variable for this command: the real one, the
        script's override, or None when the override is unknown."""
        if env is None or name not in env:
            return real
        value = env[name]
        if value is None or "$" in value or "`" in value:
            return real if value in ("$" + name, "${" + name + "}") else None
        if value == "~" or value.startswith("~/"):
            return self.home + value[1:]
        return value.rstrip("/")

    def expand(self, path: str, state: State, env: Env | None = None) -> str | None:
        """Resolve ~ and the path variables. None: somewhere unknown, such as
        under a throwaway HOME from $(mktemp -d)."""
        values: dict[str, str | None] = {
            "HOME": self._value("HOME", self.home, env),
            "XDG_CONFIG_HOME": self._value("XDG_CONFIG_HOME", self.xdg, env),
            "CLAUDE_CONFIG_DIR": self._value("CLAUDE_CONFIG_DIR", self.claude_dir, env),
            "XDG_RUNTIME_DIR": self._value("XDG_RUNTIME_DIR", self.runtime, env) if self.runtime else None,
        }
        for var, value in values.items():
            if "${" + var + "}" in path or re.search(r"\$" + var + r"(?![A-Za-z0-9_])", path):
                if value is None:
                    return None
                path = path.replace("${" + var + "}", value)
                path = re.sub(r"\$" + var + r"(?![A-Za-z0-9_])", lambda _, value=value: value, path)
        if path == "~" or path.startswith("~/"):
            home = values["HOME"]
            if home is None:
                return None
            path = home + path[1:]
        if not path.startswith("/") and not path.startswith("$"):
            path = os.path.join(state.cwd, path)
        return os.path.normpath(path) if not path.startswith("$") else path

    def lock_dirs(self) -> list[str]:
        dirs = [self.claude_dir + "/state/claude-commit-signing"]
        if self.runtime:
            dirs.append(self.runtime + "/claude-commit-signing")
        return dirs

    def classify(self, raw: str, state: State, env: Env | None = None, destructive: bool = False) -> str | None:
        path = self.expand(raw, state, env)
        if path is None:
            return None
        if path in (self.home + "/.gitconfig", self.xdg + "/git/config"):
            return "global"
        if re.search(r"(^|/)\.git/(config|modules/.+/config|worktrees/[^/]+/config\.worktree)$", path) or path.endswith(
            "/config.worktree"
        ):
            return "repo"
        # "$(git rev-parse --git-dir)/config", "$(git rev-parse --git-path config)"
        if "$(" in raw and (
            (
                re.search(r"rev-parse[^)]*--(git-dir|absolute-git-dir|git-common-dir)", raw)
                and re.search(r"config(\.worktree)?$", raw)
            )
            or re.search(r"rev-parse[^)]*--git-path\s+config(\.worktree)?\s*\)", raw)
        ):
            return "repo"
        if path.startswith(self.claude_dir + "/hooks/commit_signing_guard"):
            return "guard"
        for directory in self.lock_dirs():
            if path == directory or path.startswith(directory + "/"):
                return "guard"
        if raw.startswith(("$XDG_RUNTIME_DIR/claude-commit-signing", "${XDG_RUNTIME_DIR}/claude-commit-signing")):
            return "guard"
        # rm -rf ~/.claude takes the guard with it.
        if destructive and path in {
            self.claude_dir,
            self.claude_dir + "/hooks",
            self.claude_dir + "/state",
            self.runtime,
        } - {""}:
            return "guard"
        if path == self.claude_dir + "/settings.json" or re.fullmatch(
            re.escape(self.cwd.rstrip("/")) + r"/\.claude/settings(\.local)?\.json", path
        ):
            return "settings"
        return None

    def check_write(self, path: str, state: State, env: Env | None = None, destructive: bool = False) -> None:
        reasons = {
            "global": "write to the global git config",
            "repo": "write to a repository's git config",
            "guard": "change to the commit-signing guard",
            "settings": "shell write to Claude Code settings",
        }
        kind = self.classify(path, state, env, destructive)
        if kind:
            self.bypasses.append(reasons[kind])

    # -- scripts -----------------------------------------------------------

    def script(
        self, source: str, state: State | None = None, privileged: bool = False, depth: int = 0, top: bool = False
    ) -> None:
        if depth > MAX_DEPTH:
            return
        commands, _ = lex(source)
        # One State per ( subshell level: what a subshell changes stays in it.
        states = [state or State(self.cwd)]
        previous: Command | None = None
        for command in commands:
            while len(states) - 1 < command.depth:
                states.append(states[-1].copy())
            while len(states) - 1 > command.depth:
                states.pop()
            kind = self.command(command, states[-1], privileged, depth, previous)
            if top:
                self.kinds.append(kind)
            previous = command

    def command(self, command: Command, state: State, privileged: bool, depth: int, previous: Command | None) -> Kind:
        signing_before = len(self.signing)
        for word in command.words + [target for _, target in command.redirects]:
            for sub in word.subs:
                self.script(sub, state.copy(), privileged, depth + 1)
        for op, target in command.redirects:
            if op in WRITE_REDIRECTS:
                self.check_write(target.text, state, state.env)

        words = self.substitute(command.words, state)
        while words:
            if words[0] in KEYWORDS:
                words.pop(0)
            elif words[0] == "function" and len(words) > 1:
                words = words[2:]
            else:
                break
        if words and GIT_LOOKUP.match(words[0]):
            words[0] = "git"
        assigns: dict[str, str] = {}
        while words and ASSIGNMENT.match(words[0]):
            name, _, value = words.pop(0).partition("=")
            assigns[name] = value
        if not words:
            state.env.update(assigns)
            return "quick"

        env: Env = dict(state.env)
        env.update(assigns)
        timed = False
        while words:
            name = os.path.basename(words[0])
            if name in ("sudo", "doas", "pkexec"):
                privileged = True
                words = skip_options(words[1:], SUDO_VALUE_OPTS)
                while words and ASSIGNMENT.match(words[0]):
                    key, _, value = words.pop(0).partition("=")
                    env[key] = value
            elif name == "env":
                words = self.unwrap_env(words[1:], env)
            elif name in (
                "command",
                "builtin",
                "exec",
                "nohup",
                "time",
                "nice",
                "stdbuf",
                "ionice",
                "setsid",
                "chrt",
                "taskset",
                "timeout",
                "unbuffer",
                "flock",
            ):
                if name == "command" and words[1:2] and words[1] in ("-v", "-V"):
                    return "quick"
                if name == "flock":
                    body = self.option_value(words[1:], ("-c", "--command"))
                    if body is not None:
                        self.script(body, State(state.cwd, env, state.aliases), privileged, depth + 1)
                        return self.kind_since(signing_before, "other")
                words = skip_options(words[1:], WRAPPER_VALUE_OPTS.get(name, set()))
                if name in ("timeout", "chrt", "taskset", "flock"):
                    words = words[1:]
                timed = timed or name == "timeout"
            elif name in ("watch", "script"):
                # watch runs its arguments as a shell command; script -c runs one.
                body = (
                    self.cluster_value(words[1:], "c", "--command")
                    if name == "script"
                    else " ".join(skip_options(words[1:], {"-n", "--interval", "-d"}))
                )
                if body:
                    self.script(body, State(state.cwd, env, state.aliases), privileged, depth + 1)
                return self.kind_since(signing_before, "other")
            elif name == "find" and any(w in ("-exec", "-execdir", "-ok", "-okdir") for w in words):
                start = next(i for i, w in enumerate(words) if w in ("-exec", "-execdir", "-ok", "-okdir")) + 1
                end = next((i for i in range(start, len(words)) if words[i] in (";", "+")), len(words))
                words = words[start:end]
            elif name == "xargs":
                words = skip_options(words[1:], XARGS_VALUE_OPTS)
                # Arguments piped in from the previous command are unknown;
                # count that command's own arguments as possible ones.
                if previous is not None and previous.op in ("|", "|&"):
                    words = words + [w.text for w in previous.words[1:]]
            elif name in ("runuser", "su"):
                body = self.option_value(words[1:], ("-c", "--command"))
                if body is not None:
                    self.script(body, State(state.cwd, dict(env, HOME=None), state.aliases), True, depth + 1)
                return self.kind_since(signing_before, "other")
            elif name in SHELLS or name in ("source", "."):
                body = self.shell_body(words[1:]) if name in SHELLS else None
                for script in [body, *self.fed_scripts(command, previous)]:
                    if script is not None:
                        self.script(script, State(state.cwd, env, state.aliases), privileged, depth + 1)
                return self.kind_since(signing_before, "other")
            elif name == "eval":
                self.script(" ".join(words[1:]), State(state.cwd, env, state.aliases), privileged, depth + 1)
                return self.kind_since(signing_before, "other")
            else:
                break
        if not words:
            return "quick"

        name = os.path.basename(words[0])
        args = words[1:]
        # /usr/lib/git-core/git-commit is git commit.
        if name.startswith("git-") and name[4:] in GIT_BUILTINS:
            name, args = "git", [name[4:], *args]
        if words[0].startswith(("$", "`")):
            # A command we can't resolve: at least refuse the bypass flags.
            if any(NO_GPG_SIGN.match(a) or NO_SIGN.match(a) for a in args) or any(
                BYPASS_TEXT.search(a) for a in args if "=" in a
            ):
                self.bypasses.append("signing flags on an unresolved command")
            return "other"
        if name == "cd":
            target = args[0] if args and args[0] != "--" else (args[1] if len(args) > 1 else "~")
            state.cwd = self.expand(target, state) or state.cwd
            return "quick"
        if name in ("export", "declare", "typeset", "readonly", "local"):
            for arg in args:
                if ASSIGNMENT.match(arg):
                    key, _, value = arg.partition("=")
                    state.env[key] = value
            return "quick"
        if name == "unset":
            for arg in args:
                if not arg.startswith("-"):
                    state.env[arg] = None
            return "quick"
        if name == "git":
            kind = self.git(args, state, env, privileged, depth)
            if kind == "signing" and timed:
                self.under_timeout = True
            return kind
        self.file_command(name, args, state, env)
        return self.kind_since(signing_before, "quick" if name in QUICK_COMMANDS else "other")

    def substitute(self, words: list[Word], state: State) -> list[str]:
        """Word texts with variables the script set expanded, as far as known."""
        known = {k: v for k, v in state.env.items() if v is not None and k not in PATH_VARIABLES}
        out: list[str] = []
        for word in words:
            match = SIMPLE_VARIABLE.match(word.text)
            if match and not word.quoted and (match.group(2) or match.group(3)) in known:
                # Unquoted: the value is split into words.
                out += [w.text for c in lex(known[match.group(2) or match.group(3)])[0] for w in c.words]
                continue
            out.append(VARIABLE.sub(lambda m: known.get(m.group(2) or m.group(3), m.group(0)), word.text))
        return out

    @staticmethod
    def fed_scripts(command: Command, previous: Command | None) -> list[str]:
        """What a shell reads as its script: a heredoc, a here-string, a
        <(...) process substitution, or the output of echo, printf or cat
        piped into it."""
        scripts: list[str] = []
        for op, target in command.redirects:
            if op in ("<<", "<<-") and target.body is not None:
                scripts.append(target.body)
            elif op == "<<<":
                scripts.append(target.text)
        for word in command.words:
            if word.text.startswith("<("):
                for sub in word.subs:
                    for inner in lex(sub)[0]:
                        scripts += Guard.printed(inner)
        if previous is not None and previous.op in ("|", "|&"):
            scripts += Guard.printed(previous)
        return scripts

    @staticmethod
    def printed(command: Command) -> list[str]:
        words = [w.text for w in command.words]
        if not words or os.path.basename(words[0]) not in PRINTERS:
            return []
        out = [" ".join(a for a in words[1:] if not a.startswith("-"))]
        if words[0] == "printf":
            out.append(out[0].replace("\\n", "\n"))
        for op, target in command.redirects:
            if op in ("<<", "<<-") and target.body is not None:
                out.append(target.body)
            elif op == "<<<":
                out.append(target.text)
        return out

    def kind_since(self, signing_before: int, default: Kind) -> Kind:
        return "signing" if len(self.signing) > signing_before else default

    @staticmethod
    def cluster_value(words: list[str], letter: str, long_name: str) -> str | None:
        """The value of -<letter>, also inside a cluster such as -qc."""
        for i, word in enumerate(words):
            if word == long_name or (word.startswith("-") and not word.startswith("--") and word.endswith(letter)):
                return words[i + 1] if i + 1 < len(words) else None
            if word.startswith(long_name + "="):
                return word.split("=", 1)[1]
        return None

    @staticmethod
    def option_value(words: list[str], names: tuple[str, ...]) -> str | None:
        for i, word in enumerate(words):
            if word in names and i + 1 < len(words):
                return words[i + 1]
        return None

    @staticmethod
    def shell_body(words: list[str]) -> str | None:
        """The command string of sh -c '...' (-c may be in a cluster: -lc)."""
        i = 0
        while i < len(words):
            word = words[i]
            if word in SHELL_VALUE_OPTS:
                i += 2
                continue
            if word.startswith("-") and not word.startswith("--") and "c" in word[1:]:
                rest: list[str] = []
                j = i + 1
                while j < len(words):
                    if words[j] in SHELL_VALUE_OPTS:
                        j += 2
                        continue
                    if not words[j].startswith(("-", "+")):
                        rest.append(words[j])
                    j += 1
                return rest[0] if rest else None
            if not word.startswith(("-", "+")):
                return None
            i += 1
        return None

    def unwrap_env(self, words: list[str], env: Env) -> list[str]:
        i = 0
        while i < len(words):
            word = words[i]
            if word in ("-i", "--ignore-environment", "-"):
                env["HOME"] = None
                for key in list(env):
                    env[key] = None
            elif word in ("-u", "--unset"):
                if i + 1 < len(words):
                    env[words[i + 1]] = None
                i += 1
            elif word.startswith("--unset="):
                env[word[len("--unset=") :]] = None
            elif word.startswith("-u") and len(word) > 2:
                env[word[2:]] = None
            elif word in ("-S", "--split-string"):
                if i + 1 < len(words):
                    split = [w.text for c in lex(words[i + 1])[0] for w in c.words]
                    return split + words[i + 2 :]
            elif word.startswith("--split-string="):
                split = [w.text for c in lex(word[len("--split-string=") :])[0] for w in c.words]
                return split + words[i + 1 :]
            elif word in ("-C", "--chdir"):
                i += 1
            elif word == "--":
                i += 1
                break
            elif ASSIGNMENT.match(word):
                key, _, value = word.partition("=")
                env[key] = value
            elif not word.startswith("-"):
                break
            i += 1
        return words[i:]

    # -- git ---------------------------------------------------------------

    def git(self, args: list[str], state: State, env: Env, privileged: bool, depth: int) -> Kind:
        overrides: list[tuple[str, str | None]] = []
        i = 0
        while i < len(args):
            arg = args[i]
            if arg in GIT_VALUE_OPTS:
                if i + 1 < len(args):
                    if arg == "-c":
                        key, eq, value = args[i + 1].partition("=")
                        # A bare "-c key" sets it to true.
                        overrides.append((key, value if eq else "true"))
                    elif arg == "--config-env":
                        # The value comes from an environment variable: unknown.
                        overrides.append((args[i + 1].partition("=")[0], None))
                i += 2
                continue
            if arg.startswith("--config-env="):
                overrides.append((arg[len("--config-env=") :].partition("=")[0], None))
            elif not arg.startswith("-"):
                break
            i += 1
        sub = args[i] if i < len(args) else ""
        rest = args[i + 1 :]

        # Aliases: from -c on this command, from git config earlier in the
        # script, then the user's own config.
        aliases = dict(state.aliases)
        for key, value in overrides:
            if key.lower().startswith("alias.") and value is not None:
                aliases[key[len("alias.") :].lower()] = value
        alias = aliases.get(sub.lower())
        if alias is None and sub and sub not in GIT_BUILTINS:
            alias = self.configured_alias(sub, state)
        if alias is not None and depth < MAX_DEPTH:
            if alias.startswith("!"):
                self.script(
                    alias[1:] + " " + " ".join(rest), State(state.cwd, env, state.aliases), privileged, depth + 1
                )
                return "other"
            expanded = [w.text for c in lex(alias)[0] for w in c.words]
            if expanded:
                sub, rest = expanded[0], [*expanded[1:], *rest]

        for key, value in overrides:
            # Reading commands can't create commits, so checking signatures
            # with another verifier is fine; aliases are checked everywhere.
            if sub in READ_ONLY_GIT and not key.lower().startswith("alias."):
                continue
            reason = signing_override(key, value)
            if reason:
                self.bypasses.append("-c " + reason)

        if sub == "config":
            self.git_config(rest, state)
            return "quick"

        options = rest[: rest.index("--")] if "--" in rest else rest
        if any(NO_GPG_SIGN.match(a) for a in options):
            self.bypasses.append("--no-gpg-sign")
        if sub == "clone":
            # git clone -c key=value writes it into the new repository's config.
            for j, arg in enumerate(options):
                value: str | None = None
                if arg in ("-c", "--config", "--conf", "--confi", "--confg") and j + 1 < len(options):
                    value = options[j + 1]
                elif arg.startswith("--config="):
                    value = arg.split("=", 1)[1]
                if value is not None:
                    key, eq, setting = value.partition("=")
                    reason = signing_override(key, setting if eq else "true")
                    if reason:
                        self.bypasses.append("git clone -c " + reason)
        if sub == "tag" and any(NO_SIGN.match(a) for a in options):
            self.bypasses.append("tag --no-sign")
        if sub == "commit-tree" and not any(a.startswith("-S") or a.startswith("--gpg-sign") for a in options):
            self.bypasses.append("commit-tree without -S")
        if sub == "hash-object" and self.hash_object_writes_commit(options):
            self.bypasses.append("hash-object of a commit or tag")
        if sub in UNSIGNED_PLUMBING:
            self.bypasses.append("unsigned plumbing (git " + sub + ")")
        if sub == "stash" and rest[:1] in (["create"], ["store"]):
            self.bypasses.append("git stash " + rest[0])

        if self.git_signs(sub, options):
            if privileged or "HOME" in env:
                self.bypasses.append("HOME or user override for a signing git command")
            if any(GIT_CONFIG_ENV.match(k) and v is not None for k, v in env.items()):
                self.bypasses.append("GIT_CONFIG_* environment override")
            self.signing.append(sub)
            return "signing"
        return "slow-git" if sub in SLOW_GIT else "quick"

    def configured_alias(self, name: str, state: State) -> str | None:
        """The user's git alias for name, read with git itself (fails open)."""
        try:
            result = subprocess.run(
                ["git", "-C", state.cwd, "config", "--get", "alias." + name],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
        except OSError, subprocess.SubprocessError:
            return None
        if result.returncode != 0:
            return None
        return result.stdout.strip() or None

    @staticmethod
    def git_signs(sub: str, options: list[str]) -> bool:
        if sub in COMMIT_SUBS:
            return not any(a in NO_COMMIT_FLAGS for a in options)
        if sub == "tag":
            if any(a in TAG_READ_FLAGS or re.match(r"^-n\d*$", a) for a in options):
                return False
            return any(not a.startswith("-") for a in options)
        if sub == "push":
            return any(
                a == "--signed" or (a.startswith("--signed=") and a not in ("--signed=false", "--signed=no"))
                for a in options
            )
        return False

    @staticmethod
    def hash_object_writes_commit(options: list[str]) -> bool:
        for i, arg in enumerate(options):
            if arg in ("-t", "--type") and i + 1 < len(options) and options[i + 1] in ("commit", "tag"):
                return True
            if arg in ("-tcommit", "-ttag", "--type=commit", "--type=tag"):
                return True
        return False

    def git_config(self, args: list[str], state: State) -> None:
        action = "set"
        file: str | None = None
        if args and args[0] in CONFIG_SUBCOMMANDS:
            action = CONFIG_SUBCOMMANDS[args[0]]
            args = args[1:]
        positional: list[str] = []
        i = 0
        while i < len(args):
            arg = args[i]
            if arg == "--":
                positional += args[i + 1 :]
                break
            if arg.startswith("--"):
                name, eq, value = arg[2:].partition("=")
                option = resolve_option(name, CONFIG_OPTS)
                if option:
                    takes_value, implied = CONFIG_OPTS[option]
                    action = implied or action
                    if takes_value and not eq:
                        i += 1
                        value = args[i] if i < len(args) else ""
                    if option == "file":
                        file = value
            elif arg.startswith("-") and len(arg) > 1:
                if arg in ("-f", "-t"):
                    i += 1
                    if arg == "-f" and i < len(args):
                        file = args[i]
                elif "e" in arg[1:]:
                    action = "edit"
                elif "l" in arg[1:]:
                    action = "get"
            else:
                positional.append(arg)
            i += 1

        key = positional[0].lower() if positional else ""
        if action == "set" and key.startswith("alias.") and len(positional) >= 2:
            state.aliases[key[len("alias.") :]] = positional[1]
        if file is not None:
            # A file inside the worktree (a template or a fixture) is not a
            # config git reads, unless it lives under .git.
            path = self.expand(file, state, state.env)
            root = self.cwd.rstrip("/") + "/"
            if (
                path
                and path.startswith(root)
                and "/.git/" not in path + "/"
                and not self.classify(file, state, state.env)
            ):
                return
        signing_key = (
            key in GPGSIGN_KEYS or key in SIGNING_KEYS or key == "include.path" or key.startswith("includeif.")
        )
        if action == "edit":
            self.bypasses.append("git config --edit")
        elif action == "unset" and signing_key:
            self.bypasses.append("git config unset of " + key)
        elif action in ("remove", "rename") and key.split(".")[0].split('"')[0].strip() in SIGNING_SECTIONS:
            self.bypasses.append("git config " + action + "-section of " + key)
        elif action == "set" and len(positional) >= 2:
            reason = signing_override(key, positional[1])
            if reason:
                self.bypasses.append("git config write: " + reason)

    # -- other commands that write files ------------------------------------

    def file_command(self, name: str, args: list[str], state: State, env: Env) -> None:
        operands = [a for a in args if not a.startswith("-") or a == "-"]
        targets: list[str] = []
        if name == "tee":
            targets = operands
        elif name in ("cp", "ln", "install", "mv"):
            directory = self.option_value(args, ("-t", "--target-directory"))
            for arg in args:
                if arg.startswith("--target-directory="):
                    directory = arg.split("=", 1)[1]
            if directory:
                targets = [os.path.join(directory, os.path.basename(o)) for o in operands if o != directory]
            elif len(operands) >= 2:
                destination = operands[-1]
                targets = [destination] + [os.path.join(destination, os.path.basename(o)) for o in operands[:-1]]
            if name == "mv":
                targets += operands
        elif name in ("rm", "unlink", "truncate", "shred", "chmod", "chown", "chgrp", "chattr", "touch"):
            targets = operands
        elif name == "dd":
            targets = [a[3:] for a in args if a.startswith("of=")]
        elif name == "sed":
            if any(re.match(r"^(-[A-Za-z]*i|--in-place)", a) for a in args):
                targets = operands
        elif name == "perl":
            if any(re.match(r"^-[A-Za-z]*i", a) for a in args):
                targets = operands
        elif name in ("awk", "gawk"):
            joined = " ".join(args)
            if re.search(r"(^|\s)(-i\s*inplace|--include[= ]inplace)\b", joined):
                targets = operands
        elif name in ("ex", "ed", "vi", "vim", "nvim", "nano", "emacs", "editor"):
            targets = operands
        for target in targets:
            self.check_write(target, state, env, name in DESTRUCTIVE)

    # -- Edit, Write, MultiEdit, NotebookEdit --------------------------------

    def edit(self, tool: str, tool_input: dict[str, object]) -> None:
        path = as_str(tool_input.get("file_path")) or as_str(tool_input.get("notebook_path"))
        raw_edits = tool_input.get("edits")
        edits = [as_object(e) for e in cast(list[object], raw_edits)] if isinstance(raw_edits, list) else []
        new = "\n".join(
            as_str(t)
            for t in [
                tool_input.get("new_string"),
                tool_input.get("content"),
                tool_input.get("new_source"),
                *(e.get("new_string") for e in edits),
            ]
        )
        old = "\n".join(as_str(t) for t in [tool_input.get("old_string"), *(e.get("old_string") for e in edits)])
        state = State(self.cwd)
        kind = self.classify(path, state)
        if kind == "global":
            self.bypasses.append("edit of the global git config")
        elif kind == "repo" and (
            tool == "Write"
            or SIGNING_TEXT.search(old + "\n" + new)
            or BYPASS_TEXT.search(new)
            or re.search(r"\[\s*alias", old + "\n" + new, re.I)
        ):
            self.bypasses.append("edit of a repository's signing settings")
        elif kind == "guard":
            self.bypasses.append("change to the commit-signing guard")
        elif kind == "settings":
            if re.search(r'"disableAllHooks"\s*:\s*true', new):
                self.bypasses.append("disableAllHooks")
            elif (expanded := self.expand(path, state)) is not None and expanded == self.claude_dir + "/settings.json":
                current = old
                if tool == "Write":
                    try:
                        with open(expanded, encoding="utf-8") as f:
                            current = f.read()
                    except OSError:
                        current = ""
                if "commit_signing_guard" in current and "commit_signing_guard" not in new:
                    self.bypasses.append("removal of the commit-signing guard hook")


# ---------------------------------------------------------------------------
# Hook replies
# ---------------------------------------------------------------------------

STOP_RULES = (
    "Do not retry, do not bypass or disable signing, and do not offer an unsigned commit as an alternative. "
    "Stop any work that depends on the commit, end your turn, and tell the user that commit signing failed "
    "and needs them back at their computer. Include what is still uncommitted and any half-finished merge, "
    "rebase, cherry-pick, revert or am state the command left behind."
)
LOCKED_NOTE = "Git commands that sign are now blocked for this session until the user sends a new message. "
UNLOCKED_NOTE = "The guard could not record a lock, so you must not run git commands that sign yourself. "
FAILURE_CONTEXT = (
    "Commit signing failed for the last git command. Signing here needs the user to approve a prompt in person "
    "(for example 1Password with Windows Hello), and a failure means they are away from their computer. "
)
HANG_CONTEXT = (
    "The last git command timed out while it was most likely waiting for the user to approve signing in person "
    "(for example 1Password with Windows Hello), so they are away from their computer. It may still be running "
    "in the background: do not kill it. "
)
MAYBE_HANG_CONTEXT = (
    "The last command timed out. If a git command in it was waiting for the user to approve commit signing in "
    "person (for example 1Password with Windows Hello), they are away from their computer: do not retry, "
    "bypass or disable signing, end your turn and tell the user."
)


def bypass_reason(rule: str) -> str:
    return (
        "Blocked by the commit-signing guard (" + rule + "): this would create a commit or tag that is not signed "
        "with the user's own key, or change how git signs. Commits and tags here must always be signed by the "
        "user, and agents may never bypass, disable or redirect signing, even when asked. If signing failed, stop "
        "and tell the user so they can approve the signing prompt. If you believe this is a false positive, tell "
        "the user and let them run it themselves."
    )


LOCKED_REASON = (
    "Blocked by the commit-signing guard: commit signing failed earlier in this session. Signing needs the user "
    "to approve a prompt at their computer (for example 1Password with Windows Hello), so they are most likely "
    "away. Git commands that sign stay blocked until the user sends a new message. Do not retry, bypass or work "
    "around this. End your turn and tell the user that commit signing failed and what is still waiting to be "
    "committed."
)
ASYNC_REASON = (
    "Blocked by the commit-signing guard: run git commands that sign in the foreground with the Bash tool, so a "
    "signing failure is noticed. Signing can need the user to approve a prompt in person."
)

# Lines git prints when signing fails; it relays the signer's stderr as
# "error: <text>". Anchored to the start of the line and of the message (a \r
# precedes them in rebase output), so commit subjects ("error: could not apply
# 1a2b3c4... docs: 1Password") and file contents that mention them don't count.
SIGNING_FAILURE = re.compile(
    r"(^|[\r\n])(error|fatal): (1Password|\S*op-ssh-sign|agent returned an error|could not connect to agent"
    r"|communication with agent failed|agent refused operation|failed to fill whole buffer|Couldn't sign message"
    r"|failed to write commit object|gpg failed to sign the data|unable to sign the tag"
    r"|failed to sign the push certificate|failed reading ssh signing data buffer|user\.signingKey needs to be set)"
)
NOT_SIGNING = re.compile(r"insufficient permission for adding an object|unable to write|No space left on device")
COMMIT_CREATED = re.compile(r"(^|\n)\[[^\]\n]+ [0-9a-f]{7,}\] ")
TIMED_OUT = re.compile(r"(^|\n)Command timed out after")
# Exit status 124 from timeout(1): the tool's own "Exit code 124", or a status
# the command echoed on a line of its own ("exit=124", "rc: 124").
TIMEOUT_EXIT = re.compile(r"^Exit code 124\b|(^|\n)\W*(exit|rc|status|code)\W{0,3}124\s*($|\n)", re.I)
SYSTEM_PROMPT = re.compile(
    r"^\s*(<(task-notification|system-reminder|cross-session-message|teammate-message|channel"
    r"|coordinator-task|webhook-payload)\b|<<autonomous-loop)"
)


def deny(reason: str) -> Reply:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def context(event: str, text: str, notice: str | None = None) -> Reply:
    reply: Reply = {"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}
    if notice:
        reply["systemMessage"] = notice
    return reply


# ---------------------------------------------------------------------------
# Session lock
# ---------------------------------------------------------------------------


def _owned_dir(path: str) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid()


def lock_dir(claude_dir: str) -> str:
    # XDG_RUNTIME_DIR is private to the user and cleared at logout. Never a
    # shared /tmp, where another user could plant the directory or a symlink.
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime and _owned_dir(runtime) and os.access(runtime, os.W_OK):
        return os.path.join(runtime, "claude-commit-signing")
    return os.path.join(claude_dir, "state", "claude-commit-signing")


def set_lock(directory: str, session: str) -> bool:
    try:
        os.makedirs(os.path.dirname(directory), mode=0o700, exist_ok=True)
        with contextlib.suppress(FileExistsError):
            os.mkdir(directory, 0o700)
        if not _owned_dir(directory):
            return False
        os.close(os.open(os.path.join(directory, session), os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600))
        return True
    except OSError:
        return False


def clear_lock(directory: str, session: str) -> None:
    with contextlib.suppress(OSError):
        os.unlink(os.path.join(directory, session))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def decide(event: dict[str, object]) -> tuple[Reply | None, str | None]:
    """Return (reply or None, lock action: "set", "clear" or None)."""
    name = as_str(event.get("hook_event_name"))
    tool = as_str(event.get("tool_name"))
    tool_input = as_object(event.get("tool_input"))
    guard = Guard(event)
    session = re.sub(r"[^A-Za-z0-9_-]", "", str(event.get("session_id") or "")) or "unknown"
    directory = lock_dir(guard.claude_dir)
    guard.locked = os.path.exists(os.path.join(directory, session))

    if name == "UserPromptSubmit":
        # Only the user coming back unlocks. Results of background tasks and
        # subagents, scheduled and loop prompts, wakeups and messages from
        # other sessions also arrive as prompts.
        source = event.get("source")
        if (source is not None and source not in ("user", "sdk")) or SYSTEM_PROMPT.match(
            str(event.get("prompt") or "")
        ):
            return None, None
        clear_lock(directory, session)
        return None, "clear"

    if name == "PreToolUse" and tool in ("Bash", "Monitor"):
        guard.script(as_str(tool_input.get("command")), top=True)
        if guard.bypasses:
            return deny(bypass_reason(guard.bypasses[0])), None
        if guard.signing and guard.locked:
            return deny(LOCKED_REASON), None
        if guard.signing and (tool == "Monitor" or tool_input.get("run_in_background") is True):
            return deny(ASYNC_REASON), None
        return None, None

    if name == "PreToolUse" and tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        guard.edit(tool, tool_input)
        if guard.bypasses:
            return deny(bypass_reason(guard.bypasses[0])), None
        return None, None

    if name in ("PostToolUse", "PostToolUseFailure") and tool == "Bash":
        guard.script(as_str(tool_input.get("command")), top=True)
        raw_response = event.get("tool_response")
        response = as_object(raw_response)
        parts = [event.get("error"), response.get("stdout"), response.get("stderr"), raw_response]
        output = "\n".join(p for p in parts if isinstance(p, str))

        timed_out = (
            response.get("timedOutAfterMs") is not None
            or TIMED_OUT.search(output) is not None
            or (guard.under_timeout and TIMEOUT_EXIT.search(output) is not None)
        )
        if guard.signing and timed_out:
            if COMMIT_CREATED.search(output):
                return None, None
            # Lock only when nothing before the last signing command could be
            # the slow part (after it, nothing ran), and a commit, not just a
            # pull, was waiting.
            last = max(i for i, kind in enumerate(guard.kinds) if kind == "signing") if "signing" in guard.kinds else -1
            before = guard.kinds[:last]
            if last >= 0 and all(kind in ("quick", "signing") for kind in before) and set(guard.signing) - {"pull"}:
                ok = set_lock(directory, session)
                return context(name, HANG_CONTEXT + (LOCKED_NOTE if ok else UNLOCKED_NOTE) + STOP_RULES, NOTICE), "set"
            return context(name, MAYBE_HANG_CONTEXT), None
        # Reading a file that mentions these lines must not lock the session:
        # a signing git command, or a command that failed, has to be involved.
        if (
            (guard.signing or name == "PostToolUseFailure")
            and SIGNING_FAILURE.search(output)
            and not NOT_SIGNING.search(output)
        ):
            ok = set_lock(directory, session)
            return context(name, FAILURE_CONTEXT + (LOCKED_NOTE if ok else UNLOCKED_NOTE) + STOP_RULES, NOTICE), "set"
    return None, None


NOTICE = (
    "Commit signing failed or timed out. Git commands that sign are paused for this session until your next message."
)


def main() -> None:
    try:
        # Anything but a JSON object becomes {}, which decides nothing.
        reply, _ = decide(as_object(json.load(sys.stdin)))
    except Exception:  # a broken guard must never break Claude Code
        return
    if reply:
        json.dump(reply, sys.stdout)


if __name__ == "__main__":
    main()
