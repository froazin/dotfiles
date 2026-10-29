"""Checks for the ways of working content: the wow-* skills and rules.

Run from the repository root with `uv run pytest`.
"""

import re
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE.parent / "templates"
SKILLS = TEMPLATES / "skills"
RULES = TEMPLATES / "rules"
CORE = RULES / "wow-core.md"

MAX_LINES = 200
MAX_DESCRIPTION = 1024
MAX_NAME = 64

# The exact prefixes the wow_marker.sh hook writes into the context.
CONTEXT_PREFIXES = ("Ways of working: on", "Ways of working: off")

SKILL_NAME = re.compile(r"wow-[a-z0-9]+(?:-[a-z0-9]+)*")
FIELD = re.compile(r"([A-Za-z][\w-]*):[ \t]*(.*)")
FENCE = re.compile(r"(`{3,}|~{3,})")
CODE_SPAN = re.compile(r"(`+).+?\1")
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]*)>?(?:\s+\"[^\"]*\")?\s*\)")
REFERENCE_LINK = re.compile(r"^ {0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)")
SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*:")
# A home path, unless its next segment is a placeholder such as <user>.
HOME_PATH = re.compile(r"(?:(?:^|[\s`'\"(=:<\[,])/(?:home|Users|root)|/mnt/[a-z]/Users)/(?!<)|[A-Za-z]:\\Users\\(?!<)")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})(:?)")
ALLOWED_EMAILS = {"noreply@anthropic.com"}
ALLOWED_EMAIL_DOMAINS = ("example.com", "example.org")
# Example commit messages and PR descriptions wrap like the real thing.
MESSAGE_SKILLS = ("wow-commits", "wow-pull-requests")
MAX_MESSAGE_WIDTH = 72
# Words that would name the ways of working, or one person, in a project's
# files. Code blocks in the skills are templates and examples for projects.
PROJECT_LEAKS = re.compile(r"ways[ -]of[ -]working|\bwow[-_]|\.wow\b|\bthe user'?s\b", re.IGNORECASE)


def skill_dirs() -> list[Path]:
    return sorted(p for p in SKILLS.glob("wow-*") if p.is_dir())


def rule_files() -> list[Path]:
    return sorted(p for p in RULES.glob("wow-*.md") if p.is_file())


def wow_files() -> list[Path]:
    files = [p for d in skill_dirs() for p in d.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    return sorted(files) + rule_files()


def markdown_files() -> list[Path]:
    return [p for p in wow_files() if p.suffix == ".md"]


def text_files() -> list[Path]:
    files: list[Path] = []
    for path in wow_files():
        try:
            path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        files.append(path)
    return files


def rel(path: Path) -> str:
    return str(path.relative_to(TEMPLATES))


def frontmatter(path: Path) -> tuple[dict[str, str], str]:
    """Split a SKILL.md into its frontmatter fields and its body.

    Reads the subset of YAML a skill uses: `key: value` lines, quoted
    values and indented continuation lines (block scalars included).
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        pytest.fail(f"{rel(path)}: no frontmatter")
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        pytest.fail(f"{rel(path)}: frontmatter isn't closed with ---")
    fields: dict[str, str] = {}
    key: str | None = None
    for line in lines[1:end]:
        match = FIELD.fullmatch(line)
        if match and not line[0].isspace():
            name, value = match.group(1), match.group(2).strip()
            if re.fullmatch(r"[>|][+-]?", value):
                value = ""
            elif len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            fields[name] = value
            key = name
        elif key is not None and line.strip():
            fields[key] = f"{fields[key]} {line.strip()}".strip()
    return fields, "\n".join(lines[end + 1 :])


def prose_lines(path: Path, keep_code: bool = False) -> list[str]:
    """The lines of a Markdown file outside fenced code blocks, with code
    spans removed unless keep_code is set."""
    out: list[str] = []
    fence: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        match = FENCE.match(line.lstrip())
        if fence is None and match:
            fence = match.group(1)
            continue
        if fence is not None:
            closing = match.group(1) if match else ""
            if closing[:1] == fence[0] and len(closing) >= len(fence) and not line.strip()[len(closing) :].strip():
                fence = None
            continue
        out.append(line if keep_code else CODE_SPAN.sub("", line))
    return out


def code_block_lines(path: Path) -> list[tuple[int, str]]:
    """The numbered lines inside fenced code blocks, the complement of
    prose_lines."""
    out: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = FENCE.match(line.lstrip())
        if fence is None:
            if match:
                fence = match.group(1)
            continue
        closing = match.group(1) if match else ""
        if closing[:1] == fence[0] and len(closing) >= len(fence) and not line.strip()[len(closing) :].strip():
            fence = None
            continue
        out.append((number, line))
    return out


def anchor(heading: str) -> str:
    """GitHub's anchor for a heading: lowercase, punctuation removed,
    spaces as hyphens."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    found: set[str] = set()
    counts: dict[str, int] = {}
    for line in prose_lines(path, keep_code=True):
        match = re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
        if not match:
            continue
        base = anchor(match.group(1))
        count = counts.get(base, 0)
        counts[base] = count + 1
        found.add(f"{base}-{count}" if count else base)
    return found


def relative_links(path: Path) -> list[str]:
    links: list[str] = []
    for line in prose_lines(path):
        targets = INLINE_LINK.findall(line)
        ref = REFERENCE_LINK.match(line)
        if ref:
            targets.append(ref.group(1))
        links += [t for t in targets if t and not SCHEME.match(t) and not t.startswith("//")]
    return links


def routed_skills() -> set[str]:
    """The skills named in the last column of wow-core's routing table."""
    names: set[str] = set()
    for line in CORE.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.lstrip().startswith("|") and len(cells) >= 2:
            names.update(SKILL_NAME.findall(cells[-1]))
    return names


@pytest.mark.parametrize("skill", skill_dirs(), ids=lambda p: p.name)
def test_skill_frontmatter(skill: Path) -> None:
    path = skill / "SKILL.md"
    assert path.is_file(), f"{rel(skill)} has no SKILL.md"
    fields, body = frontmatter(path)
    name = fields.get("name", "")
    assert name == skill.name, f"{rel(path)}: name {name!r} isn't the directory name"
    assert SKILL_NAME.fullmatch(name), f"{rel(path)}: name must be wow- then lowercase letters, digits and hyphens"
    assert len(name) <= MAX_NAME, f"{rel(path)}: name is over {MAX_NAME} characters"
    description = fields.get("description", "")
    assert description, f"{rel(path)}: description is empty"
    assert len(description) <= MAX_DESCRIPTION, (
        f"{rel(path)}: description is {len(description)} characters, over {MAX_DESCRIPTION}"
    )
    assert body.strip(), f"{rel(path)}: body is empty"


@pytest.mark.parametrize("rule", rule_files(), ids=lambda p: p.name)
def test_rule_name(rule: Path) -> None:
    assert SKILL_NAME.fullmatch(rule.stem), f"{rel(rule)}: name must be wow- then lowercase letters, digits and hyphens"


def test_core_rule_routes_every_skill() -> None:
    assert CORE.is_file(), f"{rel(CORE)} is missing"
    routed = routed_skills()
    existing = {d.name for d in skill_dirs()}
    assert not existing - routed, f"skills with no row in wow-core's routing table: {sorted(existing - routed)}"
    assert not routed - existing, f"wow-core's routing table names missing skills: {sorted(routed - existing)}"


@pytest.mark.parametrize("prefix", CONTEXT_PREFIXES)
def test_core_rule_names_context_prefix(prefix: str) -> None:
    assert prefix in CORE.read_text(encoding="utf-8"), f"{rel(CORE)} doesn't mention {prefix!r}"


@pytest.mark.parametrize("path", markdown_files(), ids=rel)
def test_relative_links_resolve(path: Path) -> None:
    skill = next((d for d in skill_dirs() if path.is_relative_to(d)), None)
    for link in relative_links(path):
        target_path, _, fragment = link.partition("#")
        target = (path.parent / target_path).resolve() if target_path else path
        assert target.exists(), f"{rel(path)}: link {link!r} doesn't resolve"
        if skill is not None:
            assert target.is_relative_to(skill.resolve()), (
                f"{rel(path)}: link {link!r} leaves the skill; say 'load the wow-... skill' instead"
            )
        if fragment and target.suffix == ".md":
            assert fragment in anchors(target), f"{rel(path)}: link {link!r} names no heading"


@pytest.mark.parametrize("path", markdown_files(), ids=rel)
def test_line_limit(path: Path) -> None:
    lines = len(path.read_text(encoding="utf-8").splitlines())
    assert lines <= MAX_LINES, f"{rel(path)} is {lines} lines, over {MAX_LINES}"


@pytest.mark.parametrize("path", text_files(), ids=rel)
def test_no_home_paths(path: Path) -> None:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        assert not HOME_PATH.search(line), f"{rel(path)}:{number}: absolute home path; use ~ or a placeholder"


@pytest.mark.parametrize("path", text_files(), ids=rel)
def test_no_email_addresses(path: Path) -> None:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in EMAIL.finditer(line):
            address, domain = match.group(0).rstrip(":"), match.group(1).lower()
            if match.group(2):
                continue  # an SSH remote such as git@github.com:OWNER/REPO
            if address.lower() in ALLOWED_EMAILS:
                continue
            if any(domain == d or domain.endswith(f".{d}") for d in ALLOWED_EMAIL_DOMAINS):
                continue
            pytest.fail(f"{rel(path)}:{number}: email address {address!r}; use one at example.com")


@pytest.mark.parametrize("path", markdown_files(), ids=rel)
def test_templates_work_quietly(path: Path) -> None:
    for number, line in code_block_lines(path):
        match = PROJECT_LEAKS.search(line)
        assert not match, (
            f"{rel(path)}:{number}: {match.group(0)!r} in a code block; projects never mention "
            "the ways of working or whose conventions they follow"
        )


@pytest.mark.parametrize("skill", MESSAGE_SKILLS)
def test_message_examples_wrap(skill: str) -> None:
    path = SKILLS / skill / "SKILL.md"
    for number, line in code_block_lines(path):
        assert len(line) <= MAX_MESSAGE_WIDTH, (
            f"{rel(path)}:{number}: {len(line)} characters in an example; wrap commit bodies at {MAX_MESSAGE_WIDTH}"
        )
