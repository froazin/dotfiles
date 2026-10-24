#!/usr/bin/env python3
"""Claude Code hook: keep Claude Code session links out of everything published.

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
boundary. Standard library only. Any internal error fails open: nothing is
printed.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from typing import cast

type Reply = dict[str, object]

PATTERNS = [
    ("a Claude Code session URL", re.compile(r"claude\.ai/code/session_[A-Za-z0-9]")),
    ("a claude.ai artifact link", re.compile(r"claude\.ai/(?:code/)?artifact/[A-Za-z0-9]")),
    ("a Claude-Session trailer", re.compile(r"(?im)^[ \t]*Claude-Session:[ \t]*\S")),
    ("a Claude Code session ID", re.compile(r"\bsession_[A-Za-z0-9]{24,}\b")),
]

# Flags whose next argument is a file holding a commit message or body.
FILE_FLAGS = {"-F", "--file", "--body-file", "--notes-file"}
MAX_FILE_BYTES = 1_000_000
WRITE_TOOLS = {"Write": "content", "Edit": "new_string", "NotebookEdit": "new_source"}


def as_object(value: object) -> dict[str, object]:
    return cast(dict[str, object], value) if isinstance(value, dict) else {}


def as_list(value: object) -> list[object]:
    return cast(list[object], value) if isinstance(value, list) else []


def as_str(value: object) -> str:
    return value if isinstance(value, str) else ""


def find(text: str) -> tuple[str, str] | None:
    """The first link in text: what it is, and the line it is on."""
    for label, pattern in PATTERNS:
        match = pattern.search(text)
        if match:
            line = text[text.rfind("\n", 0, match.start()) + 1 :].split("\n", 1)[0]
            return label, line.strip()[:120]
    return None


def tokens(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def git_dir(words: list[str], cwd: str) -> str:
    for i, word in enumerate(words[:-1]):
        if word == "-C":
            return os.path.join(cwd, os.path.expanduser(words[i + 1]))
    return cwd


def file_args(words: list[str], cwd: str) -> list[str]:
    """The text of every message or body file the command passes."""
    paths: list[str] = []
    for i, word in enumerate(words):
        flag, eq, value = word.partition("=")
        if word in FILE_FLAGS and i + 1 < len(words):
            paths.append(words[i + 1])
        elif eq and flag in FILE_FLAGS:
            paths.append(value)
    base = git_dir(words, cwd)
    texts: list[str] = []
    for path in paths:
        # gh api -F takes key=value fields, not files.
        if path == "-" or "=" in path:
            continue
        full = os.path.join(base, os.path.expanduser(path))
        try:
            if os.path.isfile(full) and os.path.getsize(full) <= MAX_FILE_BYTES:
                with open(full, encoding="utf-8", errors="replace") as handle:
                    texts.append(handle.read())
        except OSError:
            pass
    return texts


def unpushed_messages(words: list[str], cwd: str) -> list[tuple[str, str]]:
    result = subprocess.run(
        ["git", "-C", git_dir(words, cwd), "log", "HEAD", "--not", "--remotes", "--format=%h%x00%B%x01"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if result.returncode != 0:
        return []
    commits: list[tuple[str, str]] = []
    for entry in result.stdout.split("\x01"):
        sha, _, body = entry.strip("\n").partition("\x00")
        if sha:
            commits.append((sha, body))
    return commits


def check_bash(command: str, cwd: str) -> str | None:
    hit = find(command)
    if hit:
        return f"The command contains {hit[0]}: {hit[1]}"
    words = tokens(command)
    if not {"git", "gh"} & set(words):
        return None
    for text in file_args(words, cwd):
        hit = find(text)
        if hit:
            return f"A message file passed to the command contains {hit[0]}: {hit[1]}"
    if "git" in words and "push" in words:
        for sha, body in unpushed_messages(words, cwd):
            hit = find(body)
            if hit:
                return f"Unpushed commit {sha} has {hit[0]} in its message: {hit[1]}. Reword it before you push"
    return None


def written_text(tool: str, tool_input: dict[str, object]) -> str:
    if tool == "MultiEdit":
        return "\n".join(as_str(as_object(edit).get("new_string")) for edit in as_list(tool_input.get("edits")))
    return as_str(tool_input.get(WRITE_TOOLS.get(tool, "")))


def check(payload: dict[str, object]) -> str | None:
    if as_str(payload.get("hook_event_name")) not in ("", "PreToolUse"):
        return None
    tool = as_str(payload.get("tool_name"))
    tool_input = as_object(payload.get("tool_input"))
    cwd = as_str(payload.get("cwd")) or os.getcwd()
    if tool in ("Bash", "Monitor"):
        return check_bash(as_str(tool_input.get("command")), cwd)
    if tool in WRITE_TOOLS or tool == "MultiEdit":
        hit = find(written_text(tool, tool_input))
        return f"The text being written contains {hit[0]}: {hit[1]}" if hit else None
    if tool.startswith("mcp__"):
        hit = find(json.dumps(tool_input, ensure_ascii=False))
        return f"The tool input contains {hit[0]}: {hit[1]}" if hit else None
    return None


def decide(payload: dict[str, object]) -> Reply | None:
    problem = check(payload)
    if not problem:
        return None
    reason = (
        f"Blocked by the no-session-links hook. {problem}. "
        "The user never wants Claude Code session links, Claude-Session trailers or claude.ai "
        "links in commits, pull requests, comments, issues, releases or files, even when Claude "
        "Code's attribution guidance asks for them. Remove the link and try again. Keep the "
        "Co-Authored-By footer. Don't work around this hook."
    )
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }


def main() -> None:
    try:
        # Anything but a JSON object becomes {}, which decides nothing.
        reply = decide(as_object(json.load(sys.stdin)))
    except Exception:  # a broken hook must never break Claude Code
        return
    if reply:
        json.dump(reply, sys.stdout)


if __name__ == "__main__":
    main()
