"""Tests for the no-session-links hook.

Run from the repository root with `uv run pytest`.
"""

import io
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import no_session_links as hook
import pytest

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE.parent / "templates"
HOOKS = TEMPLATES / "hooks"

# Made-up links, built from parts so this file holds none: the hook, once
# installed, would block writing it otherwise.
HOST = "claude" + ".ai"
SESSION_ID = "session_" + "0123456789abcdefABCDEFxyz"
SESSION_URL = f"https://{HOST}/code/{SESSION_ID}"
TRAILER = "Claude" + "-Session: " + SESSION_URL
ARTIFACT_URLS = [f"https://{HOST}/artifact/abc123", f"https://{HOST}/code/artifact/0f9e8d7c"]


def run(payload: dict[str, object], monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> str:
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(payload)))
    hook.main()
    out = capsys.readouterr().out
    if not out:
        return "allow"
    reply = hook.as_object(json.loads(out))
    return hook.as_str(hook.as_object(reply.get("hookSpecificOutput")).get("permissionDecision"))


class PreToolUse:
    """Runs the hook's entry point on a PreToolUse event in cwd, the way
    Claude Code does, and returns its decision."""

    def __init__(self, cwd: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
        self.cwd = cwd
        self._monkeypatch = monkeypatch
        self._capsys = capsys

    def __call__(self, tool: str, tool_input: dict[str, object]) -> str:
        payload: dict[str, object] = {
            "hook_event_name": "PreToolUse",
            "tool_name": tool,
            "tool_input": tool_input,
            "cwd": str(self.cwd),
        }
        return run(payload, self._monkeypatch, self._capsys)

    def bash(self, command: str) -> str:
        return self("Bash", {"command": command})


@pytest.fixture
def pre(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> PreToolUse:
    return PreToolUse(tmp_path, monkeypatch, capsys)


@pytest.mark.parametrize(
    ("expected", "command"),
    [
        ("deny", f"gh pr create --title x --body 'See {SESSION_URL}'"),
        ("deny", f"git commit -m x -m '{TRAILER}'"),
        ("deny", f"git commit -F - <<'EOF'\nfeat: x\n\n  {TRAILER}\nEOF"),
        ("deny", f"gh pr comment 1 --body {ARTIFACT_URLS[0]}"),
        ("deny", f"gh issue create --body {ARTIFACT_URLS[1]}"),
        ("deny", f"echo {SESSION_ID} >> notes.md"),
        ("deny", f"Claude-Session: {SESSION_URL}"),
        ("allow", "git commit -m 'feat: x' -m 'Co-Authored-By: Claude <noreply@anthropic.com>'"),
        ("allow", "gh pr create --body '🤖 Generated with [Claude Code](https://claude.com/claude-code)'"),
        ("allow", f"curl -fsSL https://{HOST}/install.sh | bash"),
        ("allow", "grep -nE 'claude\\.ai|Claude-Session' msg.txt"),
        ("allow", "echo 'drop claude.ai/code/session_... links'"),
        ("allow", "git commit -m 'Mention Claude-Session: in prose'"),
        ("allow", "export SESSION_ID=session_short"),
    ],
)
def test_bash(pre: PreToolUse, expected: str, command: str) -> None:
    assert pre.bash(command) == expected


def test_monitor(pre: PreToolUse) -> None:
    assert pre("Monitor", {"command": f"echo {SESSION_URL}"}) == "deny"


@pytest.mark.parametrize(
    "template",
    [
        "git commit -F {path}",
        "git commit --file={path}",
        "git -C {dir} commit -F {name}",
        "git tag -a v1 -F {path}",
        "gh pr create --title x --body-file {path}",
        "gh pr edit 2 --body-file={path}",
        "gh release create v1 --notes-file {path}",
    ],
)
def test_message_files(pre: PreToolUse, tmp_path: Path, template: str) -> None:
    message = tmp_path / "sub" / "msg.txt"
    message.parent.mkdir()
    command = template.format(path=message, dir=message.parent, name=message.name)
    message.write_text("feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n")
    assert pre.bash(command) == "allow"
    message.write_text(f"feat: x\n\n{TRAILER}\n")
    assert pre.bash(command) == "deny"


def test_message_file_relative_to_cwd(pre: PreToolUse, tmp_path: Path) -> None:
    (tmp_path / "body.md").write_text(f"Summary\n\n{SESSION_URL}\n")
    assert pre.bash("gh pr create --body-file body.md") == "deny"


def test_only_git_and_gh_files_are_read(pre: PreToolUse, tmp_path: Path) -> None:
    (tmp_path / "body.md").write_text(f"{SESSION_URL}\n")
    assert pre.bash("sort -F body.md") == "allow"
    assert pre.bash("gh api repos/o/r/issues -F title=x -F body=@body.md") == "allow"


def git(repo: Path, *args: str) -> None:
    env = {"PATH": os.environ["PATH"], "HOME": str(repo), "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"}
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, env=env)


def commit(repo: Path, message: str) -> None:
    git(repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", message)


def test_push_checks_unpushed_commits(pre: PreToolUse, tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    git(tmp_path, "init", "-q", str(repo))
    commit(repo, "feat: clean")
    assert pre.bash(f"git -C {repo} push") == "allow"
    commit(repo, f"feat: x\n\n{TRAILER}")
    assert pre.bash(f"git -C {repo} push -u origin HEAD") == "deny"
    # Once a remote has it, rewording is the user's call, not the hook's.
    git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    assert pre.bash(f"git -C {repo} push") == "allow"


@pytest.mark.parametrize(
    ("expected", "tool", "tool_input"),
    [
        ("deny", "Write", {"file_path": "/r/README.md", "content": f"Built in {SESSION_URL}\n"}),
        ("deny", "Edit", {"file_path": "/r/a.md", "old_string": "x", "new_string": ARTIFACT_URLS[0]}),
        ("allow", "Edit", {"file_path": "/r/a.md", "old_string": SESSION_URL, "new_string": "x"}),
        ("deny", "MultiEdit", {"file_path": "/r/a.md", "edits": [{"new_string": "a"}, {"new_string": TRAILER}]}),
        ("allow", "MultiEdit", {"file_path": "/r/a.md", "edits": "not a list"}),
        ("deny", "NotebookEdit", {"notebook_path": "/r/a.ipynb", "new_source": f"# {SESSION_ID}"}),
        ("deny", "mcp__github__create_pull_request", {"title": "x", "body": {"text": SESSION_URL}}),
        ("allow", "mcp__github__create_pull_request", {"title": "x", "body": "Generated with Claude Code"}),
        ("allow", "Read", {"file_path": SESSION_URL}),
        ("allow", "Write", {"file_path": "/r/a.md", "content": "See the README."}),
    ],
)
def test_tools(pre: PreToolUse, expected: str, tool: str, tool_input: dict[str, object]) -> None:
    assert pre(tool, tool_input) == expected


def test_deny_reason_names_the_link(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    payload = {
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": f"git commit -m '{TRAILER}'"},
    }
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(payload)))
    hook.main()
    reason = json.loads(capsys.readouterr().out)["hookSpecificOutput"]["permissionDecisionReason"]
    assert "a Claude Code session URL" in reason
    assert "Co-Authored-By" in reason


@pytest.mark.parametrize(
    "raw",
    [
        "",
        "not json",
        "[]",
        json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": SESSION_URL}),
        json.dumps({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": SESSION_URL}}),
    ],
)
def test_other_input_decides_nothing(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], raw: str
) -> None:
    monkeypatch.setattr(sys, "stdin", io.StringIO(raw))
    hook.main()
    assert capsys.readouterr().out == ""


def test_wrapper_ignores_shadowing_modules(tmp_path: Path) -> None:
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    for name in ("no_session_links.py", "no_session_links.sh"):
        shutil.copy(HOOKS / name, hooks)
    (hooks / "json.py").write_text("print('shadowed')\n")
    event = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": f"echo {SESSION_URL}"}}
    result = subprocess.run(
        ["sh", str(hooks / "no_session_links.sh")],
        input=json.dumps(event),
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONPATH": str(hooks)},
        check=False,
    )
    assert json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_settings_run_every_hook() -> None:
    settings = hook.as_object(json.loads((TEMPLATES / "settings.json").read_text()))
    assert hook.as_object(settings.get("attribution")).get("sessionUrl") is False
    pre_tool_use = hook.as_list(hook.as_object(settings.get("hooks")).get("PreToolUse"))
    matchers = {
        hook.as_str(hook.as_object(command).get("command")).rsplit("/", 1)[-1]: hook.as_str(
            hook.as_object(group).get("matcher")
        )
        for group in pre_tool_use
        for command in hook.as_list(hook.as_object(group).get("hooks"))
    }
    assert set(matchers["no_session_links.sh"].split("|")) >= {"Bash", "Monitor", "Write", "Edit", "mcp__.*"}
    for name in matchers:
        assert os.access(HOOKS / name, os.X_OK), name
