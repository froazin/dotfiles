---
name: wow-feature-flags
description: "House rules for feature flags in code repositories: when new or unfinished behaviour needs a flag, reading flags from environment variables, keeping them off by default, naming flag variables, landing large work as several small PRs behind a flag and how adding a flag or turning one on affects the version. Use when ways of working is on and a task adds, names or turns on a feature flag, hides new or unfinished behaviour from users, splits a large change into several pull requests or decides the version bump for flagged code."
---

# Feature flags

How to keep the default branch releasable while new behaviour is built: when to use a feature flag, how to add one and how flags affect the version. These are house defaults: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Feature flags apply only to code repositories (the wow-contributing skill describes the kinds of repository).

## Why

Every commit on the default branch must be releasable, and a project can release each commit that bumps the version as soon as it lands. So new or unfinished code mustn't change the experience for users until it's ready.

## The rules

- Read feature flags from environment variables.
- A flag is off by default. The new behaviour runs only when someone turns the flag on.
- Use a flag when a change adds new behaviour, or behaviour that isn't finished, that could change the experience for users.
- You don't need one for a change users can't see, such as a refactoring, a test, or a docs or CI change.
- From `v1.0.0`, don't hide a breaking change behind a flag.

## Naming

- If the project's `CLAUDE.md` names a prefix for flag variables, use it.
- If the project has no flags yet and no convention, ask the user before you name the first one.

## Splitting large work

Flags let a large change land as several small pull requests (PRs) that are each safe to release:

1. Land the new code behind a flag that's off.
1. Build it up over several PRs.
1. Turn the flag on in a final PR.

## How flags affect the version

New code behind a flag that's off is a patch, even when the commit type is `feat`. The commit that turns the flag on decides the bump for the hidden work:

| Hidden code | While the flag is off | Commit that turns it on |
| --- | --- | --- |
| A new feature | Patch | Minor |
| A non-breaking fix | Patch | Patch |
| A breaking change, before `v1.0.0` | Patch | Minor |
| A breaking change, from `v1.0.0` | Not allowed | Not allowed |

In alpha (`0.0.x`), every commit is a patch, including the one that turns a flag on. Load the wow-versioning skill for the full rules.

## Checklist

Before you open a PR that adds or turns on a flag, check that:

- The flag is read from an environment variable and is off by default.
- Its name follows the project's convention, or the user agreed it.
- The PR doesn't hide a breaking change behind a flag from `v1.0.0`.
- The version effect matches the table above.
