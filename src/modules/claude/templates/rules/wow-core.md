# Ways of working

House defaults for contributing and writing, held in this rule and the
`wow-*` skills.

## When it applies

- A `.wow` marker file turns the ways of working on for the directory that
  holds it and everything below it, inside the workspaces directory
  (`$WORKSPACE_DIR`, by default `~/workspaces`). Paths outside it are off.
- A hook adds a `Ways of working: on ...` or `Ways of working: off ...` line
  when a session starts and whenever the state changes for a directory you
  work in. The most recent line for the directory a task works in is the
  state for that task. With no line, it's off.
- Touching a file outside that directory, such as Claude Code's own files
  or a temporary directory, adds an off line for that file only. It doesn't
  turn the ways of working off for the task.
- When it's on, follow this rule and the `wow-*` skills for work on paths
  under the marker. When it's off, follow the project's own guidance.
- If a `wow-*` skill is denied, it's off: don't retry the skill or read its
  files another way. If the user types `/wow-<name>` themselves, follow it.
- Don't create or remove a `.wow` marker unless the user asks.

## Which guidance wins

1. The user's instructions in the session.
1. The user's other rules, such as commit signing.
1. The project's own Claude instructions: its `CLAUDE.md`, rules and
   skills, under any heading.
1. The ways of working: this rule and the `wow-*` skills.
1. The project's `CONTRIBUTING.md`, which is for external contributors. Read
   it for how to build and test the code. When it disagrees with the ways of
   working, follow the ways of working and tell the user. Don't change it
   without asking.

## Work quietly

Projects are shared, and their other contributors may not have these
skills. Unless the user asks:

- Never mention the ways of working, the `wow-*` skills, this rule or a
  `.wow` marker in anything you write for a project: its files, commit
  messages, pull requests, issues or comments.
- State a convention as the project's own, without naming where it came
  from.
- Never attribute a project's conventions to one person, such as "the
  user's conventions" or "the user prefers".

## Defaults when a project says nothing

- Every repository is a code repository: trunk-based, with pull requests
  squash-merged into `main`. A GitHub wiki takes direct commits on `master`.
- Treat a repository as public until you know. Don't tag anything unless the
  user asks, and never a release: the project's CI tags releases.
- Don't invent build, test or lint commands. Use the ones the project
  documents, or ask. If a default clearly doesn't fit, ask the user.

## Load the skill for the task

- When it's on and a task will change a repository, load `wow-contributing`
  and every skill below that the task needs before you start it, including
  any planning, research or design for it.
- Load each skill once per session. A subagent is a session of its own, and
  small edits and corrections count as tasks.
- If the user says one part of the ways of working doesn't fit, still load
  the skill and follow the rest of it.

| Before you ... | Load |
| --- | --- |
| commit, branch or push for the first time in a session | `wow-contributing` |
| write a commit message, or commit | `wow-commits` |
| open or merge a pull request, or write its title or description | `wow-pull-requests` |
| create, name or rebase a branch, or work with a fork | `wow-branching` |
| add a feature flag, or turn one on | `wow-feature-flags` |
| choose or set up how a project is versioned or released, with any tool | `wow-versioning` |
| decide whether a change bumps the version, or prepare or tag a release | `wow-versioning` |
| change anything in a GitHub wiki clone, or publish it | `wow-github-wiki` |
| write or edit docs, READMEs, `CLAUDE.md`, rules, skills, wiki pages or pull request descriptions | `wow-writing-style` |
| write or edit Markdown, including alerts, collapsed sections, task lists or footnotes | `wow-markdown` |
| add or change a diagram | `wow-diagrams` |
| write, change or trim a design doc in `docs/`, a `README.md`, `CLAUDE.md` or `CONTRIBUTING.md`, or decide where a doc belongs | `wow-repo-docs` |
| record a project's repositories, commit scopes, releases or CI in its `CLAUDE.md` | `wow-repo-docs` |
