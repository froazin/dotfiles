"""Tests for the ways-of-working marker hook (wow_marker.sh).

Each test runs the script with subprocess, the way Claude Code does, with a
throwaway HOME, WORKSPACE_DIR and XDG_RUNTIME_DIR under tmp_path. Run from the
repository root with `uv run pytest`.
"""

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import pytest

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE.parent / "templates"
SCRIPT = TEMPLATES / "hooks" / "wow_marker.sh"

# The only programs the script may run, besides sh.
UTILITIES = ("sh", "sed", "mkdir", "rmdir", "rm", "sleep")

DENY = "Ways of working is off: no directory touched in this session has a .wow marker, so wow-* skills don't apply."
OUTSIDE = "Ways of working: off (outside <workspaces>)."


def on_line(rel: str) -> str:
    shown = "<workspaces>/" + rel if rel else "<workspaces>"
    return f"Ways of working: on for {shown} (marker {shown}/.wow)."


def off_line(rel: str) -> str:
    return f"Ways of working: off for <workspaces>/{rel} (no .wow marker at or above it)."


def as_object(value: object) -> dict[str, object]:
    assert isinstance(value, dict)
    return cast("dict[str, object]", value)


@dataclass
class Result:
    code: int
    out: str
    err: str

    def context(self, event: str) -> str:
        """The additionalContext of a JSON reply, or "" when there's none."""
        if not self.out:
            return ""
        specific = as_object(as_object(json.loads(self.out)).get("hookSpecificOutput"))
        assert specific.get("hookEventName") == event
        context = specific.get("additionalContext")
        assert isinstance(context, str)
        return context


class Wow:
    """A throwaway home and workspace root, and a way to run the hook in it."""

    def __init__(self, tmp_path: Path) -> None:
        self.tmp = tmp_path
        self.home = tmp_path / "home"
        self.ws = tmp_path / "workspaces"
        self.runtime = tmp_path / "run"
        for directory in (self.home, self.ws):
            directory.mkdir()
        self.runtime.mkdir(mode=0o700)
        self.state = self.runtime / "claude-wow"
        self.env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.home),
            "WORKSPACE_DIR": str(self.ws),
            "XDG_RUNTIME_DIR": str(self.runtime),
            "LC_ALL": "C",
        }

    def dir(self, rel: str, marker: bool = False) -> Path:
        path = self.ws / rel if rel else self.ws
        path.mkdir(parents=True, exist_ok=True)
        if marker:
            (path / ".wow").touch()
        return path

    def run(
        self,
        mode: str,
        cwd: Path,
        payload: dict[str, object] | str | None = None,
        *args: str,
        env: dict[str, str] | None = None,
    ) -> Result:
        stdin = payload if isinstance(payload, str) else json.dumps(payload) if payload is not None else ""
        done = subprocess.run(
            [str(SCRIPT), mode, *args],
            input=stdin,
            cwd=cwd,
            env=env or self.env,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        result = Result(done.returncode, done.stdout, done.stderr)
        # Context never holds an absolute path, and JSON replies always parse.
        assert str(self.tmp) not in result.out + result.err
        if result.out.startswith("{"):
            json.loads(result.out)
        return result

    def status(self, cwd: Path, *args: str) -> tuple[int, str]:
        result = self.run("status", cwd, None, *args)
        return result.code, result.out.strip()

    def pre(
        self, cwd: Path, tool: str, tool_input: dict[str, object], session: str = "s1", agent: str | None = None
    ) -> str:
        payload: dict[str, object] = {
            "session_id": session,
            "hook_event_name": "PreToolUse",
            "tool_name": tool,
            "tool_input": tool_input,
            "cwd": str(cwd),
        }
        if agent is not None:
            payload["agent_id"] = agent
        result = self.run("pre-tool", cwd, payload)
        assert (result.code, result.err) == (0, "")
        assert "permissionDecision" not in result.out
        return result.context("PreToolUse")

    def read(self, cwd: Path, target: Path, session: str = "s1", agent: str | None = None) -> str:
        return self.pre(cwd, "Read", {"file_path": str(target / "file.txt")}, session, agent)

    def session_start(self, cwd: Path, session: str = "s1") -> Result:
        return self.run("session-start", cwd, {"session_id": session, "source": "startup"})

    def skill(self, cwd: Path, name: str, session: str = "s1") -> Result:
        return self.run("pre-skill", cwd, {"session_id": session, "tool_name": "Skill", "tool_input": {"skill": name}})


@pytest.fixture
def wow(tmp_path: Path) -> Wow:
    return Wow(tmp_path)


# status


def test_status_on_off_and_outside(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    assert wow.status(wow.dir("github.com/o/r/src/deep")) == (0, on_line("github.com/o/r"))
    assert wow.status(repo) == (0, on_line("github.com/o/r"))
    assert wow.status(wow.dir("github.com/o/other")) == (1, off_line("github.com/o/other"))
    assert wow.status(wow.tmp) == (1, OUTSIDE)
    assert wow.status(wow.home) == (1, OUTSIDE)


def test_status_takes_a_directory_argument(wow: Wow) -> None:
    wow.dir("github.com/o/r", marker=True)
    assert wow.status(wow.home, str(wow.ws / "github.com/o/r")) == (0, on_line("github.com/o/r"))
    assert wow.status(wow.ws, "github.com/o/r") == (0, on_line("github.com/o/r"))


def test_marker_at_root(wow: Wow) -> None:
    wow.dir("", marker=True)
    assert wow.status(wow.dir("github.com/o/r")) == (0, on_line(""))
    assert wow.status(wow.ws) == (0, on_line(""))


def test_nearest_marker_wins(wow: Wow) -> None:
    wow.dir("github.com/o/mono", marker=True)
    wow.dir("github.com/o/mono/packages/a", marker=True)
    assert wow.status(wow.dir("github.com/o/mono/packages/a/src")) == (0, on_line("github.com/o/mono/packages/a"))
    assert wow.status(wow.dir("github.com/o/mono/packages/b")) == (0, on_line("github.com/o/mono"))


def test_marker_above_root_is_ignored(wow: Wow) -> None:
    (wow.tmp / ".wow").touch()
    assert wow.status(wow.dir("github.com/o/r")) == (1, off_line("github.com/o/r"))
    assert wow.status(wow.tmp) == (1, OUTSIDE)


def test_wow_directory_does_not_count(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r")
    (repo / ".wow").mkdir()
    assert wow.status(repo) == (1, off_line("github.com/o/r"))


def test_symlinked_root_and_symlinks_resolve_physically(wow: Wow) -> None:
    real = wow.tmp / "real-workspaces"
    (real / "github.com/o/r/src").mkdir(parents=True)
    (real / "github.com/o/r/.wow").touch()
    link = wow.tmp / "ws-link"
    link.symlink_to(real)
    wow.env["WORKSPACE_DIR"] = str(link)
    assert wow.status(link / "github.com/o/r/src") == (0, on_line("github.com/o/r"))
    assert wow.status(real / "github.com/o/r/src") == (0, on_line("github.com/o/r"))
    # A link inside the root to somewhere outside it is outside.
    (real / "escape").symlink_to(wow.home)
    assert wow.status(link / "escape") == (1, OUTSIDE)


def test_missing_root_is_off(wow: Wow) -> None:
    wow.env["WORKSPACE_DIR"] = str(wow.tmp / "missing")
    assert wow.status(wow.tmp) == (1, OUTSIDE)


def test_non_existent_directory_uses_nearest_existing_ancestor(wow: Wow) -> None:
    wow.dir("github.com/o/r", marker=True)
    assert wow.status(wow.home, str(wow.ws / "github.com/o/r/new/deeper")) == (0, on_line("github.com/o/r"))
    assert wow.status(wow.home, str(wow.ws / "github.com/o/new")) == (1, off_line("github.com/o"))


def test_unsafe_characters_are_left_out_of_the_line(wow: Wow) -> None:
    wow.dir('github.com/o/we ird"repo', marker=True)
    assert wow.status(wow.dir('github.com/o/we ird"repo/src')) == (0, "Ways of working: on (marker found).")
    code, line = wow.status(wow.dir("github.com/o/sp ace"))
    assert code == 1
    assert line.startswith("Ways of working: off (")


def test_git_submodule_inherits_the_marker(wow: Wow) -> None:
    git = shutil.which("git")
    source = subprocess.run(
        ["git", "-C", str(HERE), "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
    )
    if git is None or source.returncode != 0:
        pytest.skip("needs git and a Git checkout to clone a submodule from")
    repo = wow.dir("github.com/o/parent", marker=True)
    env = {"PATH": wow.env["PATH"], "HOME": str(wow.home), "LC_ALL": "C"}
    for command in (
        ["git", "init", "-q"],
        [
            "git",
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-q",
            "--depth",
            "1",
            Path(source.stdout.strip()).as_uri(),
            "sub",
        ],
    ):
        subprocess.run(command, cwd=repo, env=env, capture_output=True, check=True)
    assert (repo / "sub" / ".git").is_file()
    assert wow.status(repo / "sub" / "src") == (0, on_line("github.com/o/parent"))


# session-start and session-end


def test_session_start_prints_only_when_on(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    on = wow.session_start(repo)
    assert (on.code, on.out, on.err) == (0, on_line("github.com/o/r") + "\n", "")
    off = wow.session_start(wow.dir("github.com/o/other"), session="s2")
    assert (off.code, off.out, off.err) == (0, "", "")


def test_session_start_resets_state(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    assert wow.read(other, repo) == on_line("github.com/o/r")
    assert (wow.state / "s1.on").exists()
    assert wow.session_start(other).out == ""
    assert not (wow.state / "s1.on").exists()
    assert (wow.state / "s1.state").read_text() == "off\n"
    # After a reset (such as /clear or a compaction) a change is told again.
    assert wow.read(other, repo) == on_line("github.com/o/r")


def test_session_end_removes_state(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    wow.session_start(repo)
    wow.read(repo, repo, agent="a1")
    (wow.state / "other.state").write_text("off\n")
    assert {p.name for p in wow.state.iterdir()} == {"s1.state", "s1.on", "s1.a1.state", "other.state"}
    assert wow.run("session-end", repo, {"session_id": "s1"}).code == 0
    assert {p.name for p in wow.state.iterdir()} == {"other.state"}


def test_state_directory_is_private(wow: Wow) -> None:
    wow.session_start(wow.dir("github.com/o/r", marker=True))
    assert wow.state.stat().st_mode & 0o777 == 0o700


def test_state_falls_back_to_the_cache_directory(wow: Wow) -> None:
    del wow.env["XDG_RUNTIME_DIR"]
    repo = wow.dir("github.com/o/r", marker=True)
    wow.session_start(repo)
    assert (wow.home / ".cache" / "claude-wow" / "s1.state").read_text() == "on:github.com/o/r\n"


# pre-tool and post-bash


@pytest.mark.parametrize(
    ("tool", "tool_input", "cwd"),
    [
        ("Read", {"file_path": "{repo}/src/a.txt"}, "{other}"),
        ("Edit", {"file_path": "{repo}/a.txt", "old_string": "a", "new_string": "b"}, "{other}"),
        ("Write", {"file_path": "{repo}/new/dir/a.txt", "content": "x"}, "{other}"),
        ("MultiEdit", {"file_path": "{repo}/a.txt", "edits": []}, "{other}"),
        ("NotebookEdit", {"notebook_path": "{repo}/n.ipynb", "new_source": ""}, "{other}"),
        ("Glob", {"pattern": "*.md", "path": "{repo}"}, "{other}"),
        ("Glob", {"pattern": "*.md", "path": "../r/src"}, "{other}"),
        ("Glob", {"pattern": "*.md"}, "{repo}"),
        ("Grep", {"pattern": "x", "path": "{repo}/src/a.txt"}, "{other}"),
        ("Grep", {"pattern": "x"}, "{repo}"),
        ("Bash", {"command": "ls"}, "{repo}"),
        ("Monitor", {"command": "tail -f log"}, "{repo}"),
    ],
)
def test_pre_tool_announces_only_on_change(wow: Wow, tool: str, tool_input: dict[str, object], cwd: str) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    (repo / "src").mkdir()
    (repo / "src" / "a.txt").touch()
    other = wow.dir("github.com/o/other")
    places = {"{repo}": str(repo), "{other}": str(other)}
    filled = {k: v.replace("{repo}", str(repo)) if isinstance(v, str) else v for k, v in tool_input.items()}
    directory = Path(places[cwd])
    wow.session_start(other)
    assert wow.pre(directory, tool, filled) == on_line("github.com/o/r")
    assert wow.pre(directory, tool, filled) == ""


def test_monorepo_on_off_on(wow: Wow) -> None:
    mono = wow.dir("github.com/o/mono")
    a = wow.dir("github.com/o/mono/a", marker=True)
    b = wow.dir("github.com/o/mono/b")
    c = wow.dir("github.com/o/mono/c", marker=True)
    assert wow.session_start(mono).out == ""
    assert wow.read(mono, mono) == ""
    assert wow.read(mono, a) == on_line("github.com/o/mono/a")
    assert wow.read(mono, a / "deeper") == ""
    assert wow.read(mono, b) == off_line("github.com/o/mono/b")
    assert wow.read(mono, mono) == ""
    assert wow.read(mono, a) == on_line("github.com/o/mono/a")
    assert wow.read(mono, c) == on_line("github.com/o/mono/c")
    assert wow.read(mono, wow.home) == OUTSIDE


def test_subagent_state_is_separate(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    assert wow.session_start(repo).out.strip() == on_line("github.com/o/r")
    started = wow.run("subagent-start", other, {"session_id": "s1", "agent_id": "a1", "agent_type": "Explore"})
    assert (started.code, started.out) == (0, "")
    assert wow.read(other, repo, agent="a1") == on_line("github.com/o/r")
    assert wow.read(other, repo, agent="a1") == ""
    assert wow.read(other, repo) == ""
    assert wow.read(other, other, agent="a2") == ""
    assert wow.read(other, repo, agent="a2") == on_line("github.com/o/r")
    on = wow.run("subagent-start", repo, {"session_id": "s1", "agent_id": "a3"})
    assert on.context("SubagentStart") == on_line("github.com/o/r")
    assert wow.read(repo, repo, agent="a3") == ""


def test_post_bash_uses_the_current_directory(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)

    def post(cwd: Path) -> str:
        payload: dict[str, object] = {
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": {"command": f"cd {other}"},
            "tool_response": {"stdout": f"{other}/x", "stderr": ""},
        }
        result = wow.run("post-bash", cwd, payload)
        assert result.code == 0
        return result.context("PostToolUse")

    assert post(repo) == on_line("github.com/o/r")
    assert post(repo) == ""
    assert post(other) == off_line("github.com/o/other")


def test_held_lock_still_announces(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    (wow.state / "s1.lock").mkdir()
    assert wow.read(other, repo) == on_line("github.com/o/r")
    assert not (wow.state / "s1.lock").exists()


# pre-skill and expand


def test_pre_skill_gate(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    for name in ("wow-commits", "plugin:wow-commits", "/wow-commits"):
        denied = wow.skill(other, name)
        assert (denied.code, denied.out, denied.err.strip()) == (2, "", DENY)
    for name in ("commit", "my-wow-thing", "plugin:other"):
        assert wow.skill(other, name) == Result(0, "", "")
    # The current directory being on is enough.
    assert wow.skill(repo, "wow-commits") == Result(0, "", "")
    # So is any directory touched in this session, even after leaving it.
    wow.read(other, repo)
    wow.read(other, other)
    assert wow.skill(other, "wow-commits") == Result(0, "", "")
    assert wow.skill(other, "plugin:wow-commits") == Result(0, "", "")
    # A subagent shares the session's flag.
    agent = wow.run("pre-skill", other, {"session_id": "s1", "agent_id": "a1", "tool_input": {"skill": "wow-commits"}})
    assert agent.code == 0


def test_expand_adds_a_note_when_off(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)

    def expand(cwd: Path, name: str) -> Result:
        result = wow.run("expand", cwd, {"session_id": "s1", "command_name": name, "prompt": "/" + name})
        assert result.code == 0
        return result

    note = expand(other, "wow-commits").context("UserPromptExpansion")
    assert note == "Ways of working: off here (no .wow marker). The user typed /wow-commits explicitly."
    assert expand(other, "review").out == ""
    assert expand(repo, "wow-commits").out == ""
    wow.read(other, repo)
    assert expand(other, "wow-commits").out == ""


# Bad input


@pytest.mark.parametrize("mode", ["session-start", "subagent-start", "pre-tool", "post-bash", "pre-skill", "expand"])
@pytest.mark.parametrize(
    "stdin",
    ["", "not json", "{", '{"session_id":', '{"session_id": 1, "tool_input": null}', "\x00\x01\n\n", "[]"],
)
def test_malformed_input_never_errors_or_blocks(wow: Wow, mode: str, stdin: str) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    result = wow.run(mode, repo, stdin)
    assert (result.code, result.err) == (0, "")


@pytest.mark.parametrize("session", ["../escape", "a b", "a/b", "a.b", "", "*"])
def test_odd_session_id_is_stateless(wow: Wow, session: str) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    assert wow.session_start(repo, session=session).out.strip() == on_line("github.com/o/r")
    # Without state, every on directory is told and off ones never are.
    assert wow.read(other, repo, session=session) == on_line("github.com/o/r")
    assert wow.read(other, repo, session=session) == on_line("github.com/o/r")
    assert wow.read(repo, other, session=session) == ""
    assert wow.run("session-end", repo, {"session_id": session}).code == 0
    assert not wow.state.exists() or not any(wow.state.iterdir())
    assert not (wow.tmp / "escape.state").exists()


def test_odd_agent_id_is_stateless(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    wow.session_start(repo)
    assert wow.read(repo, repo, agent="../x") == on_line("github.com/o/r")
    assert wow.read(repo, repo, agent="../x") == on_line("github.com/o/r")
    assert {p.name for p in wow.state.iterdir()} == {"s1.state", "s1.on"}


def test_values_with_json_escapes_are_ignored(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    escaped = str(repo).replace("/", "\\/")
    raw = '{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"' + escaped + '\\/a.txt"}}'
    result = wow.run("pre-tool", other, raw)
    assert (result.code, result.out, result.err) == (0, "", "")
    # A quote inside a value can't end it early or inject another key.
    tricky: dict[str, object] = {"session_id": "s1", "tool_input": {"file_path": f'x" ,"file_path":"{repo}/a'}}
    assert wow.run("pre-tool", other, tricky) == Result(0, "", "")
    command: dict[str, object] = {
        "session_id": "s1",
        "tool_input": {"command": f'echo "\n"skill":"x"\nfile_path={repo}/a'},
    }
    assert wow.run("pre-tool", other, command) == Result(0, "", "")
    # An escaped session id counts as no id: stateless, so on is told.
    stateless = '{"session_id":"s\\u0031","tool_input":{"file_path":"' + str(repo) + '/a"}}'
    assert wow.run("pre-tool", other, stateless).context("PreToolUse") == on_line("github.com/o/r")


def test_pretty_printed_input(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    payload = {"session_id": "s1", "tool_name": "Read", "tool_input": {"file_path": f"{repo}/a"}}
    result = wow.run("pre-tool", other, json.dumps(payload, indent=2))
    assert result.context("PreToolUse") == on_line("github.com/o/r")


def test_invalid_utf8_before_a_key_in_a_utf8_locale(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    raw = b'{"session_id":"s1","tool_input":{"content":"bad\xff","file_path":"' + str(repo).encode() + b'/a"}}'
    done = subprocess.run(
        [str(SCRIPT), "pre-tool"],
        input=raw,
        cwd=other,
        env={**wow.env, "LC_ALL": "C.UTF-8"},
        capture_output=True,
        timeout=20,
        check=False,
    )
    assert Result(done.returncode, done.stdout.decode(), "").context("PreToolUse") == on_line("github.com/o/r")


def test_marker_name_with_a_newline_is_told_once(wow: Wow) -> None:
    repo = wow.dir("github.com/o/new\nline", marker=True)
    other = wow.dir("github.com/o/other")
    wow.session_start(other)
    # JSON escapes a newline in file_path, so only the cwd can reach it.
    assert wow.pre(repo, "Bash", {"command": "true"}) == "Ways of working: on (marker found)."
    assert wow.pre(repo, "Bash", {"command": "true"}) == ""


def test_absolute_path_resolves_when_the_session_directory_is_gone(wow: Wow) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    gone = wow.dir("github.com/o/gone")
    wow.session_start(gone)
    gone.rmdir()
    # The hook falls back to cd -P . failing, so only absolute paths resolve.
    payload: dict[str, object] = {"session_id": "s1", "tool_input": {"file_path": f"{repo}/a"}}
    done = subprocess.run(
        ["sh", "-c", f'cd "{gone.parent}" && mkdir -p gone && cd gone && rmdir ../gone && exec "$0" pre-tool', SCRIPT],
        input=json.dumps(payload),
        env=wow.env,
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    assert Result(done.returncode, done.stdout, "").context("PreToolUse") == on_line("github.com/o/r")


# Environment


def test_needs_only_sh_and_basic_utilities(wow: Wow, tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in UTILITIES:
        found = shutil.which(name)
        assert found is not None, name
        (bin_dir / name).symlink_to(Path(found).resolve())
    wow.env["PATH"] = str(bin_dir)
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    assert wow.session_start(other) == Result(0, "", "")
    assert wow.skill(other, "wow-commits").code == 2
    assert wow.read(other, repo) == on_line("github.com/o/r")
    assert wow.read(other, other) == off_line("github.com/o/other")
    started = wow.run("subagent-start", repo, {"session_id": "s1", "agent_id": "a1"})
    assert started.context("SubagentStart") == on_line("github.com/o/r")
    assert wow.skill(other, "wow-commits") == Result(0, "", "")
    assert wow.run("expand", other, {"session_id": "s1", "command_name": "wow-commits"}) == Result(0, "", "")
    # A held lock makes it retry with sleep, then announce anyway.
    (wow.state / "s1.lock").mkdir()
    assert wow.read(other, repo) == on_line("github.com/o/r")
    assert wow.run("session-end", other, {"session_id": "s1"}) == Result(0, "", "")
    assert not any(wow.state.iterdir())
    assert wow.status(repo) == (0, on_line("github.com/o/r"))


EXPECTED_REGISTRATIONS = {
    ("SessionStart", None, "session-start"),
    ("SubagentStart", None, "subagent-start"),
    ("PreToolUse", "Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep|Bash|Monitor", "pre-tool"),
    ("PostToolUse", "Bash", "post-bash"),
    ("PreToolUse", "Skill", "pre-skill"),
    ("UserPromptExpansion", None, "expand"),
    ("SessionEnd", None, "session-end"),
}


def registered_commands() -> list[tuple[str, str | None, str]]:
    """Every (event, matcher, command) in settings.json that runs this hook."""
    settings = as_object(json.loads((TEMPLATES / "settings.json").read_text()))
    found: list[tuple[str, str | None, str]] = []
    for event, groups in as_object(settings.get("hooks")).items():
        assert isinstance(groups, list)
        for group in cast("list[object]", groups):
            matcher = as_object(group).get("matcher")
            assert matcher is None or isinstance(matcher, str)
            hooks = as_object(group).get("hooks")
            assert isinstance(hooks, list)
            for entry in cast("list[object]", hooks):
                command = as_object(entry).get("command")
                assert isinstance(command, str)
                if "/wow_marker.sh" in command:
                    assert as_object(entry).get("timeout") == 10
                    found.append((event, matcher, command))
    return found


def test_settings_register_every_mode() -> None:
    prefix = '"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/wow_marker.sh '
    registered = registered_commands()
    assert all(command.startswith(prefix) for _, _, command in registered)
    found = {(event, matcher, command.removeprefix(prefix)) for event, matcher, command in registered}
    assert found == EXPECTED_REGISTRATIONS
    assert len(registered) == len(EXPECTED_REGISTRATIONS)


@pytest.mark.parametrize(("event", "matcher", "command"), registered_commands())
def test_registered_command_strings_resolve(wow: Wow, event: str, matcher: str | None, command: str) -> None:
    repo = wow.dir("github.com/o/r", marker=True)
    other = wow.dir("github.com/o/other")
    payload: dict[str, object] = {"session_id": "s1", "hook_event_name": event, "cwd": str(other)}
    if event == "PreToolUse" and matcher == "Skill":
        payload |= {"tool_name": "Skill", "tool_input": {"skill": "wow-commits"}}
    elif event in ("PreToolUse", "PostToolUse"):
        payload |= {"tool_name": "Bash", "tool_input": {"command": "ls"}}
    elif event == "UserPromptExpansion":
        payload |= {"command_name": "wow-commits"}
    env = {**wow.env, "CLAUDE_CONFIG_DIR": str(TEMPLATES)}
    done = subprocess.run(
        ["sh", "-c", command],
        input=json.dumps(payload),
        cwd=other,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    # From an unmarked directory: only the skill gate speaks, and it denies.
    if matcher == "Skill":
        assert (done.returncode, done.stderr.strip()) == (2, DENY)
    elif event == "UserPromptExpansion":
        assert done.returncode == 0
        assert "off here" in done.stdout
    else:
        assert (done.returncode, done.stdout, done.stderr) == (0, "", "")
    # From a marked one, the start hooks and the Bash hooks tell Claude.
    done = subprocess.run(
        ["sh", "-c", command], input=json.dumps(payload), cwd=repo, env=env, capture_output=True, text=True, check=False
    )
    assert (done.returncode, done.stderr) == (0, "")
    if (
        event in ("SessionStart", "SubagentStart", "PostToolUse")
        or matcher == "Read|Edit|Write|MultiEdit|NotebookEdit|Glob|Grep|Bash|Monitor"
    ):
        assert "Ways of working: on for <workspaces>/github.com/o/r" in done.stdout
