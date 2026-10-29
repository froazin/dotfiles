---
name: wow-branching
description: "House trunk-based branching for code repositories: branching from the latest default branch, branch names (feature/, bugfix/ or other/ plus a lowercase hyphenated slug), keeping branches short-lived, rebasing rather than merging the default branch in, force-pushing with --force-with-lease and working from a fork. Use when ways of working is on and a task creates, names, renames or pushes a branch, rebases or updates a branch on the default branch, resolves a rebase conflict, force-pushes after a rebase, splits a large change across branches or works on a pull request from a fork."
---

# Branching

How changes move from a short-lived branch to the default branch in a code repository: trunk-based development, branch names, rebasing and working from a fork. These are house defaults: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Direct-commit repositories and GitHub wikis have no branches to name: commit on the default branch (the wow-contributing skill describes the kinds of repository).

## The rules at a glance

- Branch from the latest default branch, and keep the branch short-lived.
- Keep each pull request (PR) small and focused on one change.
- Name branches `<type>/<slug>`. See [Branch names](#branch-names).
- Keep the branch current by rebasing on the default branch. Never merge the default branch into it.
- Put new or unfinished behaviour behind a feature flag (load the wow-feature-flags skill), so the default branch is always safe to release.
- PRs are squash-merged. There are no merge commits on the default branch.

## Trunk-based development

The default branch, usually `main`, is the trunk. It's protected: every change goes through a PR, and nobody pushes to it directly.

1. Create a branch from the latest default branch.
1. Make one focused change on it.
1. Open a PR as soon as the change is ready.

There are no release branches, and no long-running development or integration branches. Releases are made from the default branch.

### Keep branches short-lived

The longer a branch lives, the further it drifts from the default branch, and the harder it is to review and rebase.

If a change is too big for one small PR, split it into several that each land on their own, with unfinished behaviour hidden behind a feature flag. For example, one PR adds the new code behind a flag that's off, later ones fill it in, and a final one turns the flag on.

## Branch names

A branch name is a type, a `/` and a slug. The slug uses lowercase letters and digits, with words separated by hyphens.

| Type | Use it for |
| --- | --- |
| `feature` | Anything that adds new functionality |
| `bugfix` | Anything that fixes a bug |
| `other` | Anything that isn't a feature or a bug fix |

```text
feature/version-flag
bugfix/empty-server-url
other/update-readme
```

- Use only these three types. Unlike [GitVersion](https://gitversion.net/), which inspired the names, there's no `release` type.
- Keep the slug short, and describe the one change the branch carries.
- Don't use uppercase letters, underscores, dots or extra `/` separators in the slug.
- The rules apply to branches in the project's own repositories, not to branches in an external contributor's fork.

## Working on a branch

From the repository, or with `git -C <path>` from elsewhere:

```bash
git switch main
git pull --ff-only
git switch -c feature/<slug>
```

Commit on the branch, then push it once the user agrees:

```bash
git push -u origin feature/<slug>
```

Then open a PR from the branch to the default branch (load the wow-pull-requests skill).

## Keeping the branch current

When the default branch moves on, rebase the branch on it:

```bash
git fetch origin
git rebase origin/main
```

- If the rebase stops on a conflict, resolve it, stage the files and run `git rebase --continue`. To give up and put the branch back as it was, run `git rebase --abort`.
- Rebasing rewrites the branch's commits, so push it with `git push --force-with-lease`. That refuses to overwrite commits on the remote that you haven't fetched.

> [!WARNING]
> Only rebase and force-push your own branch. Never force-push the default branch, and never use plain `--force`.

## Working from a fork

External contributors can't create branches in the project's repositories. They fork the repository, work on a branch in the fork and open a PR from it to the default branch. The project's `CONTRIBUTING.md` tells them how.

When you work on a fork's PR, the upstream repository is usually the `upstream` remote, so a fork rebases with:

```bash
git fetch upstream
git rebase upstream/main
```

## Checklist

Before you push a branch, check that:

- It was created from the latest default branch.
- Its name is `feature/`, `bugfix/` or `other/` plus a lowercase hyphenated slug.
- It carries one focused change.
- It's rebased on the default branch, with no merge commits.
- The user has agreed to the push.
