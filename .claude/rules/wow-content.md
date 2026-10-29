---
paths:
  - "src/modules/claude/templates/skills/wow-*/**"
  - "src/modules/claude/templates/rules/wow-*.md"
---

# Ways of working content

The `wow-*` skills and rules in the claude module hold house defaults, and
people copy them from this public repository.

## Keep it generic and publishable

- State every rule directly, as the project's own. Never name, cite or link
  another source of the guidance, a private repository or setup steps
  outside this repository.
- No real names, emails, usernames, hostnames, GitHub handles or personal
  paths such as `/home/<name>`. Use placeholders: `OWNER/REPO`, `<you>`,
  `jdoe`, `example.com`.
- Don't hard-code a model name in a co-author example. Write
  `Co-Authored-By: Claude <noreply@anthropic.com>`, and say to use the
  attribution line the session gives, exactly as given.
- Leave out third-party GitHub handles and repository URLs you only
  observed. Cite official docs, such as docs.github.com, or describe the
  behaviour generically.
- Frame the house style as defaults that a project's own `CLAUDE.md` can
  override, under any heading.
- Never tell an agent to mention the ways of working, the `wow-*` skills or
  a `.wow` marker in a project's files, or to attribute a project's
  conventions to one person. Templates and examples in code blocks are
  copied into projects, and a test checks them.

## Structure

- `rules/wow-core.md` loads in every session, including for people with no
  `.wow` marker, so keep it short and give it no `paths` frontmatter.
- Each skill is `skills/<name>/SKILL.md`, with longer material in
  `skills/<name>/references/*.md`, one level deep. Link to a skill's own
  references with relative links, such as `references/markup.md`.
- Between skills, write "load the wow-X skill", never a relative link.
- State each fact in one place, and point to the skill that holds it.
- Every new skill gets a row in the routing table in `wow-core.md`. Remove
  the row when you remove the skill.
- The `Ways of working: on` and `Ways of working: off` prefixes in
  `wow-core.md` match what `hooks/wow_marker.sh` writes. Change them together.

## Limits

- Skill and rule names start with `wow-`. A skill's frontmatter `name`
  matches its directory, and needs no fields other than `name` and
  `description` unless one is needed.
- A `description` is at most 1024 characters. Keep it to task triggers, in
  the words a request would use, and say it applies when the ways of working
  are on.
- Keep each file under 200 lines. A reference over 100 lines gets a
  `## Contents` list after its intro.

## Style and checks

- Follow the house style in the `wow-writing-style`, `wow-markdown` and
  `wow-diagrams` skills in `src/modules/claude/templates/skills/`.
- Run `uv run pytest src/modules/claude/tests/test_wow_content.py` after
  every change, and keep it green. It checks names, descriptions, the
  routing table, links, line counts, home paths and email addresses.
