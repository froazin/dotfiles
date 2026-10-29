---
name: wow-pull-requests
description: "House rules for squash-merged pull requests: the title written as a commit header without the PR number, the description written as a commit body with no footers, closing issues, marking breaking changes, [skip ci], keeping PRs small, PRs from forks or tools and the checklist before review. Use when ways of working is on and a task opens, creates, drafts or edits a pull request, writes or changes its title or description, adds attribution to a PR or decides how it credits a co-author, closes an issue through a PR or gets a PR ready for review."
---

# Pull requests

How to title and describe a pull request (PR), and how it lands on the default branch. These are house defaults: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Only code repositories take PRs. Direct-commit repositories and GitHub wikis don't (the wow-contributing skill describes the kinds of repository). For the header format, load the wow-commits skill. For branches and rebasing, load the wow-branching skill.

## How a PR becomes a commit

PRs are squash-merged: GitHub squashes all of a PR's commits into one commit on the default branch, and builds that commit's message from the PR. Commits are the change log, so write the PR as though it were a commit.

| PR field | Becomes | Format |
| --- | --- | --- |
| Title | The commit header (first line) | A commit header |
| Description | The commit body | A commit body. GitHub adds the co-author trailers |

Every PR lands as a single commit. There are no merge commits, and the history stays linear.

## Write the title

Write the title as the first line of a commit message, with no issue reference. It can end with `[skip ci]` (see [Skip CI](#skip-ci)):

```text
type(scope)!: Description [skip ci]
```

For example:

```text
feat(cli): Add a version flag
```

### Don't add a reference

GitHub appends the PR number in brackets when it merges. Don't type it yourself, and don't put an issue reference in the title: reference issues from the description (see [Close an issue](#close-an-issue)). If the PR above is #321, it lands as:

```text
feat(cli): Add a version flag (#321)
```

The PR number links the commit to its review. This is the same place a direct commit puts its issue reference (load the wow-commits skill).

## Write the description

Write the description as the body of a commit message: what changed on the branch and why. Add no footers.

```text
Add a --version flag that prints the version the binary was built with.
```

Everything in the description becomes part of the history on the default branch.

### Co-authors come from the branch's commits

Don't put a `Co-Authored-By:` footer in the description. When GitHub squash-merges a PR, it collects the co-authors from the trailers of the branch's commits and adds a `Co-authored-by:` line for each one at the end of the message, after a `---------` line. A footer in the description would appear twice, and it would no longer be in the final paragraph, where Git and GitHub read trailers.

So credit a co-author on the commits instead: every commit with AI-generated code ends with the `Co-Authored-By:` footer (load the wow-commits skill). Leave the lines GitHub adds in the merge box as they are.

### When Claude writes the description

- If the session gives an attribution line for PR descriptions, add it exactly as given, as the last paragraph of the description.
- Every commit Claude makes on the branch ends with the session's commit attribution lines, which is how the squashed commit credits Claude.

## Close an issue

Reference issues from the description, never the title. To close an issue, add a line with a closing keyword, such as `Closes #123`. GitHub links the issue to the PR, and closes it when the squashed commit lands on the default branch. If the PR only contributes to the issue, mention it without a keyword, such as `Part of #123`. The wow-commits skill lists the closing keywords.

Don't end the description with that line. When the branch has no co-authors, GitHub adds nothing after the description, so the line would be the commit's last paragraph, which Conventional Commits reads as a footer. Put it before the last paragraph of prose.

## Mark a breaking change

Mark a breaking change with a `!` before the colon in the title, never with a `BREAKING CHANGE:` footer. Start the description with what breaks, why, who is affected and what to do instead. The wow-commits skill has the full rule. A title and the start of its description:

```text
feat(sdk)!: Stream encoded json in the read command response
```

```text
The read command now streams its response as encoded json instead of
returning one decoded object. Callers that index into the response must
read the stream and decode it themselves, as the read example now does.

Streaming keeps memory flat for large responses.
```

Load the wow-versioning skill for the version bump, and for the Go module path rule when a PR moves to `v2` or later.

## Keep PRs small

- Make one change per PR. The PR becomes one commit, and one entry in the change log.
- Split large work into several PRs that each make sense on their own. Hide unfinished behaviour behind a feature flag (load the wow-feature-flags skill).
- Keep the branch current by rebasing it on the default branch. Never merge the default branch into it.

## Skip CI

`[skip ci]` goes at the end of the title, in special cases only. GitHub keeps it when it merges and adds the PR number after it (observed), so `chore(docs): Fix typo in readme [skip ci]` lands as `chore(docs): Fix typo in readme [skip ci] (#321)`. Don't use it on a PR that should bump the version: it would skip the workflows for the squashed commit on the default branch, which can include the release. The wow-commits skill has the full rule.

## PRs from forks and tools

- External contributors open PRs from a fork (the wow-branching skill covers forks). The title and description rules in this skill still apply.
- Tools such as Dependabot open their own PRs. Don't rewrite their titles.

## After the merge

- The squashed commit decides the next version (load the wow-versioning skill). Don't tag a release unless the user asks.

## Checklist

Before you ask for a review, check that:

- The title is a valid commit header, without the PR number or any issue reference.
- The description reads as a commit body, with no footers.
- Any issue the PR closes is referenced in the description with a closing keyword, such as `Closes #123`.
- A breaking change has `!` in the title and a description that starts with what breaks, why, who is affected and what to do instead.
- A Go module PR that moves to `v2` or later adds the major version suffix to the module path.
- The title doesn't contain `[skip ci]` if the PR should bump the version, unless the reviewers agree to an exception.
- The description has no `Co-Authored-By:` footer. Each commit on the branch with AI-generated code has one instead.
- A description Claude wrote carries the session's attribution line for PRs, if it gives one.
- The PR makes one focused change, and the branch is rebased on the default branch.
