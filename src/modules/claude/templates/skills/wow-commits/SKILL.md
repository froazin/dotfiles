---
name: wow-commits
description: "House commit message format: Conventional Commits headers with optional bracketed issue reference and [skip ci] fields, scopes, case rules, the body, breaking changes, footers and the Co-Authored-By footer for AI-generated code. Use when ways of working is on and a task writes, amends or rewords a commit message, commits in any repository, checks a commit header, references or closes an issue from a commit, skips CI for a commit, marks a breaking change or adds a Co-Authored-By or other trailer."
---

# Commit messages

How to write a commit message: the header format, the body, footers, issue references, `[skip ci]`, breaking changes and the AI co-author footer. The format is a house default: where the `## Ways of working` section of the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

The format applies to every kind of repository (the wow-contributing skill describes the kinds). Issue references, `[skip ci]` and version effects only matter in code repositories. In a code repository, pull requests (PRs) are squash-merged, so a PR's title and description are written in this format too (load the wow-pull-requests skill).

## Format

Every commit follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), with one extension: optional bracketed fields between the type and the scope.

```text
type[ref](scope)!: Description

<body>

<footer-token>: <value>
```

Separate the header (the first line), the optional body and the optional footers with one blank line. A typical commit:

```text
feat[#123](logging): Add a timestamp to log messages

A longer description of the change.

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Header

| Part | Required | What it is | Example |
| --- | --- | --- | --- |
| `type` | Yes | The kind of change. Lowercase only | `feat`, `fix`, `refactor`, `chore` |
| `[ref]` | No | One or two bracketed fields: an issue reference, `[skip ci]`, or both as `[#123][skip ci]` | `[#123]`, `[close #123]`, `[skip ci]` |
| `(scope)` | No, but recommended | The area of the project the change affects. Lowercase only | `(logging)`, `(docs)`, `(claude)` |
| `!` | Only for breaking changes | Marks a breaking change. Goes straight before the colon | `feat(sdk)!:` |
| `: Description` | Yes | A colon, one space, then a short summary written as an instruction | `: Add a timestamp to log messages` |

- **Type.** Conventional Commits defines `feat` (a new feature) and `fix` (a bug fix). Also use `refactor`, `chore`, `test`, `ci` and other conventional types where they fit. The type doesn't decide the version bump: what the commit changes does (load the wow-versioning skill).
- **Scope.** Include one whenever the change has a clear area. A project can list its usual scopes in its `## Ways of working` section.
- **Description.** Write it as an instruction, starting with a capital letter: "Add a timestamp to log messages", "Fix typo in readme". Don't end it with a full stop.
- **Bracket fields.** They're a house extension, not part of the Conventional Commits spec. When a header has both an issue reference and `[skip ci]`, put the issue reference first: `chore[#123][skip ci](docs): Fix typo in readme`.

### Case rules

- The type and the scope are strictly lowercase. `Feat` and `(Logging)` aren't allowed.
- Everything else can use upper and lower case letters, digits and the symbols Conventional Commits allows, plus `#` for issue and PR IDs.

## Body

The body is optional. Use it to explain what changed and why, in more detail than the header allows.

```text
fix[close #123](ipc): Bounds check the piped input string

Check the length of piped input before reading it, so a long input can't overflow the buffer.

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Issue references

Code repositories only. Put the issue ID in square brackets between the type and the scope. GitHub turns `#123` into a link to issue 123.

| Bracket field | Meaning |
| --- | --- |
| `[#123]` | Contributes to issue 123 without closing it |
| `[close #123]`, `[resolve #123]` | Closes issue 123 when the commit lands on the default branch |

- GitHub's closing keywords are `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves` and `resolved`.
- Use a closing keyword only when the change fully resolves the issue. If the issue needs more work, use the plain `[#123]` form so GitHub doesn't close it.
- Leave the reference out when the commit doesn't relate to an issue.

## Skipping CI

Code repositories only. In special cases, such as a typo fix in a README, add `[skip ci]` to the header so GitHub doesn't run CI workflows for the commit:

```text
chore[skip ci](docs): Fix typo in readme
```

- GitHub accepts several forms of the marker. Use `[skip ci]` only.
- Don't use it on a commit that should bump the version. On the default branch it also skips that commit's workflows, which can include the release. Raise any exception in the PR for the reviewers to decide.
- Skipped workflows leave required checks pending, which can block a merge.
- If the project has no CI yet, the rule still applies, so the history stays right once CI is added.

## Breaking changes

A change that isn't backward compatible needs **both** of these:

- A `!` straight before the colon in the header.
- A `BREAKING CHANGE:` footer, with the token in uppercase, that explains why the change isn't backward compatible.

```text
feat(sdk)!: Stream encoded json in the read command response

Longer change description.

BREAKING CHANGE: Why this change is not API backward compatible.

Co-Authored-By: Claude <noreply@anthropic.com>
```

What a breaking change does to the version depends on whether the project has reached `v1.0.0`. Load the wow-versioning skill.

## Footers and AI attribution

- If an AI agent generated any of the code in a commit, a `Co-Authored-By` footer naming the agent is mandatory, in every kind of repository.
- Use the attribution lines the session gives, exactly as given, such as the `Co-Authored-By:` line and any other trailers. The session's line usually names the model. The examples in this skill show only the form. The user's own rules still come first (see the wow-core rule).
- Write the `Co-Authored-By:` value as `Name <email>`, with the email address inside angle brackets: `Co-Authored-By: Claude <noreply@anthropic.com>`. GitHub only credits a co-author written in this form. If a session's line leaves out the brackets, add them.
- Put footers in the final paragraph, after any `BREAKING CHANGE:` footer, with nothing after them. Git and GitHub only read trailers from the last paragraph.

## Commits made by tools

Some commits are made by tools, such as Dependabot's dependency updates, which arrive with headers like `chore(deps): bump the gomod group with 2 updates`. Don't write these by hand, and don't reword them. The wow-versioning skill says how dependency updates affect the version.

## Checklist

Before you commit, check that:

- The header follows `type[ref](scope)!: Description`, with the type and scope in lowercase.
- An issue reference uses a closing keyword only if the commit resolves the issue.
- `[skip ci]` is used only in a special case, after any issue reference, and not on a commit that bumps the version.
- A breaking change has both a `!` and a `BREAKING CHANGE:` footer.
- A commit with AI-generated code ends with the session's `Co-Authored-By` footer, in the last paragraph, with the email address in angle brackets.
