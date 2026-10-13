"""Tests for the commit-signing guard hook.

Run from the repository root with `uv run pytest`. Command cases live in
commit_signing_guard.cases; structural cases (the Edit and Write tools,
timeouts, background runs, the lock lifecycle) are below.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import NamedTuple

import commit_signing_guard as guard
import pytest

HERE = Path(__file__).resolve().parent
HOOKS = HERE.parent / "templates" / "hooks"
CASES = HERE / "commit_signing_guard.cases"
HOME = "/home/u"
SESSION = "test-session"


class Case(NamedTuple):
    line: int
    kind: str
    text: str


def load_cases() -> list[Case]:
    cases: list[Case] = []
    for number, line in enumerate(CASES.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip() and not line.startswith("#"):
            kind, _, text = line.partition(" ")
            cases.append(Case(number, kind, text))
    return cases


def case_id(case: Case) -> str:
    return f"line{case.line}-{case.kind}"


def hook_output(reply: dict[str, object] | None) -> dict[str, object]:
    return guard.as_object((reply or {}).get("hookSpecificOutput"))


def decision(reply: dict[str, object] | None) -> str:
    return guard.as_str(hook_output(reply).get("permissionDecision")) or "allow"


def context(reply: dict[str, object] | None) -> str:
    return guard.as_str(hook_output(reply).get("additionalContext"))


class Hook:
    """Runs the hook's entry point the way Claude Code does: JSON on stdin,
    a JSON reply (or nothing) on stdout."""

    def __init__(self, runtime: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
        self.runtime = runtime
        self._monkeypatch = monkeypatch
        self._capsys = capsys

    def run_raw(self, raw: str) -> str:
        self._monkeypatch.setattr(sys, "stdin", io.StringIO(raw))
        guard.main()
        return self._capsys.readouterr().out

    def run(self, event: dict[str, object]) -> dict[str, object] | None:
        out = self.run_raw(json.dumps({"session_id": SESSION, "cwd": "/r", **event}))
        return guard.as_object(json.loads(out)) if out else None

    def lock(self, locked: bool) -> Path:
        path = self.runtime / "claude-commit-signing" / SESSION
        if locked:
            path.parent.mkdir(mode=0o700, exist_ok=True)
            path.touch()
        else:
            path.unlink(missing_ok=True)
        return path

    def pre(self, tool: str, tool_input: dict[str, object]) -> str:
        return decision(self.run({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": tool_input}))

    def post(self, event: str, command: str, output: str, **response: object) -> dict[str, object] | None:
        payload: dict[str, object] = {"hook_event_name": event, "tool_name": "Bash", "tool_input": {"command": command}}
        if event == "PostToolUseFailure":
            payload["error"] = output
        else:
            payload["tool_response"] = {"stdout": output, "stderr": "", **response}
        return self.run(payload)


@pytest.fixture
def runtime(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A clean environment: HOME is /home/u and the lock lives in tmp_path."""
    directory = tmp_path / "runtime"
    directory.mkdir(mode=0o700)
    for name in list(os.environ):
        if name != "PATH":
            monkeypatch.delenv(name)
    monkeypatch.setenv("HOME", HOME)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(directory))
    return directory


@pytest.fixture
def hook(runtime: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> Hook:
    return Hook(runtime, monkeypatch, capsys)


# ---------------------------------------------------------------------------
# Command cases
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("case", load_cases(), ids=case_id)
def test_case(hook: Hook, case: Case) -> None:
    if case.kind in ("deny", "allow", "locked-deny", "locked-allow"):
        hook.lock(case.kind.startswith("locked"))
        expected = case.kind.rsplit("-", 1)[-1]
        assert hook.pre("Bash", {"command": case.text.replace("{NL}", "\n")}) == expected
    elif case.kind in ("lock", "none"):
        path = hook.lock(False)
        head, _, output = case.text.partition(" ||| ")
        event, _, command = head.partition(" ")
        hook.post(event, command.replace("{NL}", "\n"), output.replace("\\n", "\n").replace("\\r", "\r"))
        assert path.exists() == (case.kind == "lock")
    else:
        pytest.fail(f"unknown case kind {case.kind!r}")


# ---------------------------------------------------------------------------
# The session lock
# ---------------------------------------------------------------------------


def test_lock_lifecycle(hook: Hook) -> None:
    path = hook.lock(False)
    assert hook.pre("Bash", {"command": "git commit -m x"}) == "allow"
    reply = hook.post(
        "PostToolUseFailure",
        "git commit -m x",
        "Exit code 128\nerror: 1Password: failed to fill whole buffer\nfatal: failed to write commit object",
    )
    assert path.exists()
    assert reply is not None and "systemMessage" in reply
    assert "Commit signing failed" in context(reply)
    assert hook.pre("Bash", {"command": "git commit -m x"}) == "deny"
    # Background task and subagent results arrive as prompts, but are not the user.
    hook.run({"hook_event_name": "UserPromptSubmit", "prompt": "<task-notification>\n<task-id>a</task-id>"})
    assert path.exists()
    hook.run({"hook_event_name": "UserPromptSubmit", "prompt": "I'm back, try again"})
    assert not path.exists()
    assert hook.pre("Bash", {"command": "git commit -m x"}) == "allow"


def test_other_sessions_unaffected(hook: Hook) -> None:
    hook.lock(True)
    event: dict[str, object] = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "session_id": "other",
        "tool_input": {"command": "git commit -m x"},
    }
    assert hook.run(event) is None


@pytest.mark.parametrize("source", ["schedule_wakeup", "loop_wakeup", "cron"])
def test_scheduled_prompts_do_not_unlock(hook: Hook, source: str) -> None:
    path = hook.lock(True)
    hook.run({"hook_event_name": "UserPromptSubmit", "source": source, "prompt": "continue TODO.md"})
    assert path.exists()


def test_messages_from_other_sessions_do_not_unlock(hook: Hook) -> None:
    path = hook.lock(True)
    hook.run({"hook_event_name": "UserPromptSubmit", "prompt": "<teammate-message>hi</teammate-message>"})
    assert path.exists()
    hook.run({"hook_event_name": "UserPromptSubmit", "source": "user", "prompt": "back"})
    assert not path.exists()


def test_unwritable_lock_dir_still_tells_the_model(hook: Hook) -> None:
    directory = hook.runtime / "claude-commit-signing"
    directory.mkdir(mode=0o500)
    try:
        reply = hook.post(
            "PostToolUseFailure", "git commit -m x", "Exit code 128\nfatal: failed to write commit object"
        )
        assert "could not record a lock" in context(reply)
    finally:
        directory.chmod(0o700)


# ---------------------------------------------------------------------------
# Timeouts and asynchronous runs
# ---------------------------------------------------------------------------


def test_hang_moved_to_background(hook: Hook) -> None:
    path = hook.lock(False)
    reply = hook.post("PostToolUse", "git add a && git commit -m x", "", backgroundTaskId="b1", timedOutAfterMs=120000)
    assert path.exists()
    assert "do not kill it" in context(reply)


def test_slow_command_before_commit_only_warns(hook: Hook) -> None:
    path = hook.lock(False)
    reply = hook.post("PostToolUse", "npm test && git commit -m x", "", backgroundTaskId="b1", timedOutAfterMs=120000)
    assert not path.exists()
    assert "If a git command" in context(reply)


@pytest.mark.parametrize(
    ("tool", "tool_input", "expected"),
    [
        ("Bash", {"command": "git commit -m x", "run_in_background": True}, "deny"),
        ("Bash", {"command": "npm run dev", "run_in_background": True}, "allow"),
        ("Monitor", {"command": "git commit -am wip"}, "deny"),
        ("Monitor", {"command": "tail -f log"}, "allow"),
    ],
)
def test_background_and_monitor(hook: Hook, tool: str, tool_input: dict[str, object], expected: str) -> None:
    assert hook.pre(tool, tool_input) == expected


# ---------------------------------------------------------------------------
# Edit, Write and MultiEdit
# ---------------------------------------------------------------------------

SETTINGS = HOME + "/.claude/settings.json"
DISABLE_HOOKS = '{"disableAllHooks": true,'


@pytest.mark.parametrize(
    ("expected", "tool", "tool_input"),
    [
        ("deny", "Edit", {"file_path": HOME + "/.gitconfig", "old_string": "[commit]", "new_string": "[nocommit]"}),
        ("deny", "Edit", {"file_path": HOME + "/.config/git/config", "old_string": "a", "new_string": "b"}),
        ("deny", "Write", {"file_path": HOME + "/.gitconfig", "content": "[user]"}),
        (
            "deny",
            "Edit",
            {"file_path": "/r/.git/config", "old_string": "signingkey = a", "new_string": "signingkey = b"},
        ),
        ("deny", "Edit", {"file_path": "/r/.git/modules/sub/config", "old_string": "", "new_string": "[commit]"}),
        (
            "deny",
            "Edit",
            {"file_path": "/r/.git/config", "old_string": "[core]", "new_string": "[alias]\n\tci = commit"},
        ),
        ("deny", "Write", {"file_path": "/r/.git/config", "content": "[core]"}),
        (
            "deny",
            "MultiEdit",
            {"file_path": "/r/.git/config", "edits": [{"old_string": "x", "new_string": "[commit]"}]},
        ),
        ("deny", "Write", {"file_path": HOME + "/.claude/hooks/commit_signing_guard.py", "content": ""}),
        ("deny", "Edit", {"file_path": SETTINGS, "old_string": "{", "new_string": DISABLE_HOOKS}),
        (
            "deny",
            "Edit",
            {"file_path": "/r/.claude/settings.local.json", "old_string": "{", "new_string": DISABLE_HOOKS},
        ),
        ("deny", "Edit", {"file_path": SETTINGS, "old_string": '"commit_signing_guard.sh"', "new_string": '"true"'}),
        ("allow", "Edit", {"file_path": SETTINGS, "old_string": '"model": "a"', "new_string": '"model": "b"'}),
        ("allow", "Edit", {"file_path": "/r/.git/config", "old_string": "url = a", "new_string": "url = b"}),
        ("allow", "Write", {"file_path": "/r/src/modules/git/templates/.gitconfig", "content": "[core]"}),
        ("allow", "Write", {"file_path": "/r/dotfiles/.config/git/config", "content": "[pull]"}),
        ("allow", "Edit", {"file_path": "/r/README.md", "old_string": "gpgsign", "new_string": "commit.gpgsign"}),
        ("allow", "Write", {"file_path": "/r/src/modules/claude/templates/settings.json", "content": "{}"}),
        (
            "allow",
            "Edit",
            {"file_path": "/r/.claude/worktrees/claude-commit-signing/a.md", "old_string": "a", "new_string": "b"},
        ),
    ],
)
def test_edit_and_write(hook: Hook, expected: str, tool: str, tool_input: dict[str, object]) -> None:
    assert hook.pre(tool, tool_input) == expected


# ---------------------------------------------------------------------------
# Robustness
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "raw",
    ["", "not json", "[]", '{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": "x"}'],
)
def test_broken_input_fails_open(hook: Hook, raw: str) -> None:
    assert hook.run_raw(raw) == ""


def test_pathological_command_is_fast(hook: Hook) -> None:
    command = ": " + "git " * 9000 + "; git -c commit.gpgsign=false commit -m x"
    start = time.monotonic()
    assert hook.pre("Bash", {"command": command}) == "deny"
    assert time.monotonic() - start < 2


def test_configured_alias(hook: Hook, tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "alias.ci", "commit"], check=True)
    event: dict[str, object] = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "cwd": str(repo),
        "tool_input": {"command": "git ci -m x"},
    }
    assert hook.run(event) is None
    hook.lock(True)
    assert decision(hook.run(event)) == "deny"


def test_wrapper_ignores_shadowing_modules(tmp_path: Path) -> None:
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    for name in ("commit_signing_guard.py", "commit_signing_guard.sh"):
        shutil.copy(HOOKS / name, hooks)
    (hooks / "json.py").write_text("print('shadowed')\n")
    event = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "session_id": "s",
        "cwd": "/r",
        "tool_input": {"command": "git commit --no-gpg-sign -m x"},
    }
    result = subprocess.run(
        ["sh", str(hooks / "commit_signing_guard.sh")],
        input=json.dumps(event),
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONPATH": str(hooks)},
        check=False,
    )
    assert decision(guard.as_object(json.loads(result.stdout))) == "deny"
