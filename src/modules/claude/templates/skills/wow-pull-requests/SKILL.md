---
name: wow-pull-requests
description: "House rules for squash-merged pull requests: the title written as a commit header without the PR number, the description written as a commit body with footers last, closing issues, marking breaking changes, [skip ci], keeping PRs small, PRs from forks or tools and the checklist before review. Use when ways of working is on and a task opens, creates, drafts or edits a pull request, writes or changes its title or description, adds attribution to a PR or decides how it credits a co-author, closes an issue through a PR or gets a PR ready for review."
---

# Pull requests

How to title and describe a pull request (PR), and how it lands on the default branch. These are house defaults: where the `## Ways of working` section of the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Only code repositories take PRs. Direct-commit repositories and GitHub wikis don't (the wow-contributing skill describes the kinds of repository). For the header format, load the wow-commits skill. For branches and rebasing, load the wow-branching skill.

## How a PR becomes a commit

PRs are squash-merged: GitHub squashes all of a PR's commits into one commit on the default branch, and builds that commit's message from the PR. Commits are the change log, so write the PR as though it were a commit.

| PR field | Becomes | Format |
| --- | --- | --- |
| Title | The commit header (first line) | A commit header |
| Description | The commit body and footers | A commit body, then any footers |

Every PR lands as a single commit. There are no merge commits, and the history stays linear.

## Write the title

Write the title exactly as the first line of a commit message:

```text
type[ref](scope)!: Description
```

For example:

```text
feat[resolve #123](cli): Add a version flag
```

### Don't add the PR number

GitHub appends the PR number in brackets when it merges. Don't type it yourself. If the PR above is #321, it lands as:

```text
feat[resolve #123](cli): Add a version flag (#321)
```

The PR number in `()` links the commit to its review. The issue reference in `[]` links it to the issue, and here closes it.

## Write the description

Write the description as the body of a commit message: what changed on the branch and why. Then add any footers, such as `BREAKING CHANGE:`.

```text
Add a --version flag that prints the version the binary was built with.
```

Everything in the description becomes part of the history on the default branch.

### Co-authors come from the branch's commits

Don't put a `Co-Authored-By:` footer in the description. When GitHub squash-merges a PR, it collects the co-authors from the trailers of the branch's commits and adds a `Co-authored-by:` line for each one at the end of the message, after a `---------` line. A footer in the description would appear twice, and it would no longer be in the final paragraph, where Git and GitHub read trailers.

So credit a co-author on the commits instead: every commit with AI-generated code ends with the `Co-Authored-By:` footer (load the wow-commits skill). Leave the lines GitHub adds in the merge box as they are.

### When Claude writes the description

- If the session gives an attribution line for PR descriptions, add it exactly as given, as the last paragraph of the body, before any footers.
- Keep any footers, such as `BREAKING CHANGE:`, as the final paragraph of the description, with nothing after them.
- Every commit Claude makes on the branch ends with the session's commit attribution lines, which is how the squashed commit credits Claude.

## Close an issue

Put a closing keyword and the issue number in the title's brackets, such as `fix[close #123](ipc): ...`. GitHub closes the issue when the squashed commit lands on the default branch. If the PR only contributes to the issue, use `[#123]`. The wow-commits skill lists the closing keywords.

## Mark a breaking change

A breaking change needs **both** a `!` before the colon in the title and a `BREAKING CHANGE:` footer at the end of the description.

```text
Longer change description.

BREAKING CHANGE: Why this change is not API backward compatible.
```

Load the wow-versioning skill for the version bump, and for the Go module path rule when a PR moves to `v2` or later.

## Keep PRs small

- Make one change per PR. The PR becomes one commit, and one entry in the change log.
- Split large work into several PRs that each make sense on their own. Hide unfinished behaviour behind a feature flag (load the wow-feature-flags skill).
- Keep the branch current by rebasing it on the default branch. Never merge the default branch into it.

## Skip CI

`[skip ci]` goes in the title, after any issue reference, in special cases only. Don't use it on a PR that should bump the version: it would skip the workflows for the squashed commit on the default branch, which can include the release. The wow-commits skill has the full rule.

## PRs from forks and tools

- External contributors open PRs from a fork (the wow-branching skill covers forks). The title and description rules in this skill still apply.
- Tools such as Dependabot open their own PRs. Don't rewrite their titles.

## After the merge

- The squashed commit decides the next version (load the wow-versioning skill). Don't tag a release unless the user asks.

## Checklist

Before you ask for a review, check that:

- The title is a valid commit header, without the PR number.
- The description reads as a commit body, with any footers as the final paragraph.
- Any issue the PR closes is referenced in the title with a closing keyword.
- A breaking change has both `!` in the title and a `BREAKING CHANGE:` footer.
- A Go module PR that moves to `v2` or later adds the major version suffix to the module path.
- The title doesn't contain `[skip ci]` if the PR should bump the version, unless the reviewers agree to an exception.
- The description has no `Co-Authored-By:` footer. Each commit on the branch with AI-generated code has one instead.
- A description Claude wrote carries the session's attribution line for PRs, if it gives one, before any footers.
- The PR makes one focused change, and the branch is rebased on the default branch.
