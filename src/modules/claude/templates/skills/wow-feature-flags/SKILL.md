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

The version comes from the commit types, which commitizen reads (load the wow-versioning skill). Type each commit by what it does for users who turn the flag on:

- **It adds behaviour they can reach,** even though the flag is off by default: `feat`, a minor bump.
- **It fixes, refactors or speeds up behaviour they can reach:** `fix`, `refactor` or `perf`, a patch. Building a feature up over several PRs doesn't make every PR a `feat`.
- **They can never reach it,** even with the flag on, such as groundwork that a later PR wires in: `refactor`, a patch. The commit that makes it reachable is typed by what it adds.

| Hidden code | Commit while the flag is off | Commit that turns it on by default |
| --- | --- | --- |
| A new feature users can turn on | `feat`: minor | `feat`: minor |
| A non-breaking fix | `fix`: patch | `fix`: patch |
| A breaking change, before `v1.0.0` | `feat`, without `!`: minor. Users only opt in to it, so it isn't a breaking change yet. Say in the body what will break when it's turned on | `feat!`, with the breaking change body: minor |
| A breaking change, from `v1.0.0` | Not allowed | Not allowed |

## Checklist

Before you open a PR that adds or turns on a flag, check that:

- The flag is read from an environment variable and is off by default.
- Its name follows the project's convention, or the user agreed it.
- The PR doesn't hide a breaking change behind a flag from `v1.0.0`.
- Each commit's type matches what it does for users who turn the flag on, and code they can never reach is a `refactor`.
