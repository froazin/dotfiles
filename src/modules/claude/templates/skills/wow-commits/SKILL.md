---
name: wow-commits
description: "House commit message format: Conventional Commits headers ending in an optional [skip ci] and issue reference such as (#123), scopes, case rules, the body, breaking changes (marked with ! and explained in the body) and the Co-Authored-By footer for AI-generated code, the only footer. Use when ways of working is on and a task writes, amends or rewords a commit message, commits in any repository, checks a commit header, references or closes an issue from a commit, skips CI for a commit, marks a breaking change or adds a Co-Authored-By or other trailer."
---

# Commit messages

How to write a commit message: the header format, the body, issue references, `[skip ci]`, breaking changes and the AI co-author footer. The format is a house default: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

The format applies to every kind of repository (the wow-contributing skill describes the kinds). Issue references, `[skip ci]` and version effects only matter in code repositories. In a code repository, pull requests (PRs) are squash-merged, so a PR's title and description are written in this format too (load the wow-pull-requests skill).

## Format

Every commit follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). The header can end with `[skip ci]` and an issue reference, in the same places GitHub puts them in a squash-merged PR's commit, so every tool that reads Conventional Commits can parse it.

```text
type(scope)!: Description [skip ci] (#123)

<body>

---------

Co-Authored-By: Claude <noreply@anthropic.com>
```

Separate the header (the first line), the optional body and the co-author footer with one blank line. The co-author footer is the only footer, and it comes last, after a `---------` line (see [Co-author footer](#co-author-footer)). Don't add other footers, such as `BREAKING CHANGE:`. A typical commit:

```text
feat(logging): Add a timestamp to log messages (#123)

A longer description of the change.

---------

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Header

| Part | Required | What it is | Example |
| --- | --- | --- | --- |
| `type` | Yes | The kind of change. Lowercase only | `feat`, `fix`, `refactor`, `chore` |
| `(scope)` | No, but recommended | The area of the project the change affects. Lowercase only | `(logging)`, `(docs)`, `(claude)` |
| `!` | Only for breaking changes | Marks a breaking change. Goes straight before the colon | `feat(sdk)!:` |
| `: Description` | Yes | A colon, one space, then a short summary written as an instruction | `: Add a timestamp to log messages` |
| ` [skip ci]` | No | Skips CI for the commit. See [Skipping CI](#skipping-ci) | `: Fix typo in readme [skip ci]` |
| ` (#123)` | No | The issue the commit relates to. See [Issue references](#issue-references) | `: Add a version flag (#123)` |

- **Type.** Conventional Commits defines `feat` (a new feature) and `fix` (a bug fix). Also use `refactor`, `chore`, `test`, `ci` and other conventional types where they fit. The type doesn't decide the version bump: what the commit changes does (load the wow-versioning skill).
- **Scope.** Include one whenever the change has a clear area. A project can list its usual scopes in its `CLAUDE.md`.
- **Description.** Write it as an instruction, starting with a capital letter: "Add a timestamp to log messages", "Fix typo in readme". Don't end it with a full stop.
- **Ending.** `[skip ci]` and the issue reference are part of the description as far as Conventional Commits is concerned. When a header has both, put `[skip ci]` first: `chore(docs): Fix typo in readme [skip ci] (#123)`. That's the order GitHub produces when it adds a PR number (observed).

### Case rules

- The type and the scope are strictly lowercase. `Feat` and `(Logging)` aren't allowed.
- Everything else can use upper and lower case letters, digits and the symbols Conventional Commits allows, plus `#` for issue and PR IDs.

## Body

The body is optional, except for a breaking change (see [Breaking changes](#breaking-changes)). Use it to explain what changed and why, in more detail than the header allows.

```text
fix(ipc): Bounds check the piped input string (#123)

Check the length of piped input before reading it, so a long input can't overflow the buffer.

Closes #123

---------

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Issue references

Code repositories only. GitHub turns `#123` into a link to issue 123.

| Where | Write | Meaning |
| --- | --- | --- |
| End of the header, in brackets | `(#123)` | The commit relates to issue 123. It links the issue but never closes it |
| A line in the body | `Closes #123` | Closes issue 123 when the commit lands on the default branch |

- GitHub's closing keywords are `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves` and `resolved`.
- Use a closing keyword only when the change fully resolves the issue. If the issue needs more work, keep only the `(#123)` in the header so GitHub doesn't close it.
- Never make the `Closes #123` line the last paragraph. Conventional Commits reads a `Token #value` line there as a footer, and the co-author footer is the only footer. Put it before a paragraph of prose, or straight before the `---------` separator.
- A PR's title carries no issue reference: GitHub adds the PR number when it merges. Reference issues from the PR's description instead (load the wow-pull-requests skill).
- Leave the reference out when the commit doesn't relate to an issue.

## Skipping CI

Code repositories only. In special cases, such as a typo fix in a README, end the header's description with `[skip ci]` so GitHub doesn't run CI workflows for the commit:

```text
chore(docs): Fix typo in readme [skip ci]
```

- GitHub accepts several forms of the marker. Use `[skip ci]` only, before any issue reference.
- Don't use it on a commit that should bump the version. On the default branch it also skips that commit's workflows, which can include the release. Raise any exception in the PR for the reviewers to decide.
- Skipped workflows leave required checks pending, which can block a merge.
- If the project has no CI yet, the rule still applies, so the history stays right once CI is added.

## Breaking changes

Mark a change that isn't backward compatible with a `!` straight before the colon in the header, and nothing else: never a `BREAKING CHANGE:` footer.

- The `!` sits in the header, which no merge rewrites. Conventional Commits 1.0.0 allows it on its own, and tools that follow that spec read it as a breaking change, such as commitlint, release-please, git-cliff and semantic-release with the `conventionalcommits` preset. semantic-release's default `angular` preset doesn't read `!`.
- A footer stops being a Git trailer once GitHub adds its `---------` line and co-author trailers after a PR description. One marker in the header avoids two that can disagree.
- Don't start any body line with `BREAKING CHANGE:` either: release tools would still read it as a footer.
- Write the header's description as the change users will notice. With `!`, the spec makes the description describe the breaking change.
- The body is required. Start it with what breaks, why, who is affected and what to do instead. Then describe the rest of the change.

```text
feat(sdk)!: Stream encoded json in the read command response

The read command now streams its response as encoded json instead of
returning one decoded object. Callers that index into the response must
read the stream and decode it themselves, as the read example now does.

Streaming keeps memory flat for large responses.

---------

Co-Authored-By: Claude <noreply@anthropic.com>
```

What a breaking change does to the version depends on whether the project has reached `v1.0.0`. Load the wow-versioning skill.

## Co-author footer

- If an AI agent generated any of the code in a commit, a `Co-Authored-By` footer naming the agent is mandatory, in every kind of repository.
- Use the attribution lines the session gives, exactly as given. The session's line usually names the model. The examples in this skill show only the form. The user's own rules still come first (see the wow-core rule). Any attribution that isn't a `Co-Authored-By:` line, such as a "Generated with" sentence, goes in the body, before the separator.
- Write the `Co-Authored-By:` value as `Name <email>`, with the email address inside angle brackets: `Co-Authored-By: Claude <noreply@anthropic.com>`. GitHub only credits a co-author written in this form. If a session's line leaves out the brackets, add them.
- Put the co-author lines in the final paragraph, with nothing after them. Git and GitHub only read trailers from the last paragraph.
- Before that final paragraph, add a paragraph that holds only `---------`, with a blank line on each side. GitHub's merge box adds the same line before the co-author trailers when it squash-merges a PR (observed), so commits made directly and through PRs end the same way.
- Use exactly nine hyphens. Git takes a line that is `---` followed by a space or the end of the line as the start of a patch: it finds no trailers after it, and `git am` (and `git rebase --apply`, which calls it) cuts the message there. So no line anywhere in a commit message or PR description may be `---` on its own or start with `--- `, such as a Markdown horizontal rule.
- In a squash-merged PR, the footer goes on each commit on the branch, not in the PR description: GitHub's merge box adds the separator and the footer from the commits (load the wow-pull-requests skill). Leave them as they are.

## Commits made by tools

Some commits are made by tools, such as Dependabot's dependency updates, which arrive with headers like `chore(deps): bump the gomod group with 2 updates`. Don't write these by hand, and don't reword them. The wow-versioning skill says how dependency updates affect the version.

## Checklist

Before you commit, check that:

- The header follows `type(scope)!: Description`, with the type and scope in lowercase. Any `[skip ci]` and `(#123)` end the description, in that order.
- A `Closes #123` line goes in the body, only when the commit fully resolves the issue, and never as the last paragraph.
- `[skip ci]` is used only in a special case, and not on a commit that bumps the version.
- A breaking change has a `!` in the header and a body that starts with what breaks, why, who is affected and what to do instead.
- The only footer is the co-author footer: no `BREAKING CHANGE:` or other footers.
- A commit with AI-generated code ends with the session's `Co-Authored-By` footer, in the last paragraph, with the email address in angle brackets.
- A `---------` paragraph of exactly nine hyphens comes straight before the co-author trailers.

## Sources

- https://www.conventionalcommits.org/en/v1.0.0/
- https://git-scm.com/docs/git-interpret-trailers
- https://git-scm.com/docs/git-am
- https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
- https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/skipping-workflow-runs
- https://docs.github.com/en/pull-requests/committing-changes-to-your-project/creating-and-editing-commits/creating-a-commit-with-multiple-authors
- https://github.com/conventional-changelog/conventional-changelog/tree/master/packages/conventional-changelog-conventionalcommits
