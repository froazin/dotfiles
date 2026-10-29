---
name: wow-contributing
description: "House contributing rules for internal contributors (the user and Claude): the principles, the kinds of repository (code, direct-commit and GitHub wiki), knowing which repository and branch you're in, keeping private values out of public repositories and Git safety for pushes, force-pushes, staging, signing and tags. Use when ways of working is on and a task commits, branches or pushes for the first time in a session, pushes or force-pushes, decides how a change lands in a repository, works across several clones side by side, checks whether a repository is public or finds a repository's default branch. Takes precedence over the project's CONTRIBUTING.md, which is for external contributors."
---

# Contributing

How changes land in a project's repositories: the principles, the kinds of repository and the rules for every commit and push. It's for internal contributors, meaning the user and Claude agents working with these skills. External contributors follow the project's own `CONTRIBUTING.md`.

Load this skill first, then the skill for the task:

| Before you ... | Load |
| --- | --- |
| write a commit message, or commit | the wow-commits skill |
| open a pull request (PR), or write its title or description | the wow-pull-requests skill |
| create, name or rebase a branch, or work with a fork | the wow-branching skill |
| add a feature flag, or turn one on | the wow-feature-flags skill |
| decide whether a change bumps the version, or tag a release | the wow-versioning skill |

## Principles

- **Trunk-based development.** All code changes land on the default branch through PRs. Branches are short-lived, and there are no release branches.
- **Small, focused PRs.** Each PR makes one change and is squash-merged, so it lands as one commit. History stays linear, with no merge commits.
- **Commits are the change log.** Every commit follows [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) with the extensions in the wow-commits skill. A PR's title and description become its commit message.
- **Every commit on the default branch is releasable.** New or unfinished behaviour that could change the experience for users goes behind a feature flag that's off by default.
- **AI-assisted work is credited.** Every commit that includes AI-generated code has a `Co-Authored-By` footer.

## Project specifics come first

The rules in this skill and the other contributing skills are house defaults. A project can state its own specifics in its `CLAUDE.md`, usually in an optional `## Contributing` section (load the wow-repo-docs skill). The wow-core rule gives the full order of precedence and the defaults when a project says nothing.

- Where the project's `CLAUDE.md` and these rules disagree, follow the project.
- Where the project's `CONTRIBUTING.md` and these rules disagree, follow these rules, and tell the user about the difference. `CONTRIBUTING.md` is written for external contributors.

## Kinds of repository

| Kind | Default branch | How changes land | Branches, PRs and feature flags | Drives a version |
| --- | --- | --- | --- | --- |
| Code repository | `main` | PR from a short-lived branch, squash-merged | Yes | Yes |
| Direct-commit repository | `main` | Commit directly on the default branch | No | No |
| GitHub wiki | `master` | Commit directly on `master`. A push publishes | No | No |

- Treat a repository as a code repository unless the project says otherwise.
- A direct-commit repository is one the project names as such. It's usually a private repository with one owner.
- A GitHub wiki always takes direct commits, because wikis have no PRs. Load the wow-github-wiki skill before you change one.
- Every kind uses the Conventional Commits header. Issue references, `[skip ci]`, versions and CI apply only to code repositories.
- If the project doesn't state the default branch, find it with `git symbolic-ref --short refs/remotes/origin/HEAD`.

## Know which repository you're in

- Before you commit, check the repository and branch with `git status`.
- When a project has several clones side by side, run Git with `-C <path>` rather than `cd`, so every command shows which repository it acts on.
- `gh` has no `-C` option. Run it in a subshell, for example `(cd <path> && gh pr create)`.

## Public and private

- Anything in a public repository's files, commits, branch names, PRs and issues is visible to everyone. Never put tokens, credentials, internal hostnames, account URLs, personal paths such as `/home/<user>/...` or private identifiers there. Use placeholders.
- If the project doesn't state a repository's visibility, check it with `gh repo view --json visibility`. Treat the repository as public until you know.
- Never write a token into any file, even in a private repository.

## Git safety

- Ask the user before every push, and say what it changes. A push to a public branch is visible straight away, and a push to a wiki's `master` publishes it.
- Never force-push the default branch, and never use plain `--force`. After a rebase, use `--force-with-lease`, and only on your own branch.
- Stage files by name rather than with `git add -A`, so you don't commit an untracked file by accident.
- Commits and tags are signed. If signing fails, stop and tell the user, as the user's commit-signing rule says. Don't retry it or work around it.
- Don't create or push a release tag unless the user asks.
- Don't invent build, test or lint commands. Use only the ones the project documents.

## Checklist

Before you commit or push, check that:

- You're in the right repository, on the right branch for its kind.
- The commit message follows the wow-commits skill.
- Nothing private is going into a public repository.
- The user has agreed to the push.
