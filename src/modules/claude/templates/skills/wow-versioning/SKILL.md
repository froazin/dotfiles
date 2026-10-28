---
name: wow-versioning
description: "House Semantic Versioning rules for code repositories: how what a commit changes, not its type, decides a major, minor, patch or no bump; the alpha (0.0.x) and beta (0.x.y) stages before v1.0.0; breaking changes; release tags with a v prefix; continuous delivery; and the Go module path suffix from v2. Use when ways of working is on and a task decides whether a change bumps the version, works out the next version, marks a breaking change, creates or pushes a release tag, prepares a release, moves a project to v0.1.0 or v1.0.0 or moves a Go module to v2 or later."
---

# Versioning

How a commit changes a project's version, how releases are tagged and what changes at `v1.0.0`. These are house defaults: where the `## Ways of working` section of the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Only code repositories have versions. Commits in direct-commit repositories and GitHub wikis never change a version (the wow-contributing skill describes the kinds of repository). A project without releases says so in its `## Ways of working` section. Its commits still follow these rules, so the history is right when releases start.

## Semantic Versioning

Projects use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`, such as `1.2.3`.

| Part | Example | A change to it means |
| --- | --- | --- |
| `MAJOR` | **1**.2.3 | Breaking changes, from `v1.0.0` |
| `MINOR` | 1.**2**.3 | New features and capabilities, and breaking changes in beta, before `v1.0.0` |
| `PATCH` | 1.2.**3** | Fixes, refactorings and dependency updates that don't fit the other two, and every change in alpha |

## How a commit changes the version

What a commit changes decides the bump, not its type. Start at the top and use the first row that matches:

| What the commit changes | Bump | Example |
| --- | --- | --- |
| Nothing in the source code, whatever its type. For example docs, CI or tests | None | `v1.4.2` stays `v1.4.2` |
| The source code in any way, while the version is `0.0.x` (alpha). Includes a breaking change and a new feature | Patch | `v0.0.3` to `v0.0.4` |
| The source code, in a way that isn't backward compatible, from `v1.0.0` | Major | `v1.4.2` to `v2.0.0` |
| The source code, in a way that isn't backward compatible, from `v0.1.0` and before `v1.0.0` (beta), and not behind a flag that's off. Includes turning on a breaking change that was behind a flag | Minor | `v0.3.1` to `v0.4.0` |
| The source code, adding a feature or capability users can use (not behind a flag that's off). Includes turning on a feature that was behind a flag | Minor | `v1.4.2` to `v1.5.0` |
| The source code in any other way: a fix, a refactoring, a dependency update that changes the build artifact, new code behind a flag that's off (even a breaking change in beta), or turning on a non-breaking fix that was behind a flag | Patch | `v1.4.2` to `v1.4.3` |

- **Source code** is code that's reflected in the final build artifact. CI configuration, tests and docs aren't source code.
- Content wins over type. A `feat(docs):` commit that doesn't touch the source code doesn't bump the version.
- A dependency update is a patch when it changes the build artifact, and no bump when it only affects tests or tooling.
- Mark every breaking change with a `!` in the header, and start the body with what breaks, why, who is affected and what to do instead, whatever its type and whatever the version (load the wow-commits skill).
- For flags, load the wow-feature-flags skill.

## Before the stable release

Before `v1.0.0`, the project isn't considered stable. It goes through two stages:

| Stage | Versions | A breaking change | A new feature | Anything else |
| --- | --- | --- | --- | --- |
| Alpha | `0.0.x` | Patch | Patch | Patch |
| Beta | `0.x.y`, from `v0.1.0` | Minor | Minor | Patch |

- In alpha, every change to the source code bumps the patch version, even a breaking change. A `feat!:` commit at `v0.0.3` gives `v0.0.4`.
- In beta, a breaking change to the source code bumps the minor version, whatever its type. A `fix(ipc)!:` commit at `v0.3.1` gives `v0.4.0`.
- A breaking change hidden behind a flag that's off is a patch while it's hidden. The commit that turns the flag on is a minor bump in beta, and a patch in alpha.
- The first release is `v0.1.0`, unless the project says otherwise, such as by starting in alpha at `v0.0.1`.
- The project moves from alpha to beta at `v0.1.0`, and to `v1.0.0`, when the maintainer decides it's ready.

## From `v1.0.0`

The project is considered stable:

- Every breaking change to the source code, including a breaking fix, bumps the major version.
- Breaking changes mustn't be hidden behind a feature flag.
- If a breaking change is ever absolutely necessary, the maintainer plans it at the time.

## Tags and releases

- Tag each release in Git with its version and a `v` prefix, such as `v1.0.2`. Always include the `v`.
- Tags are signed, like commits. Don't create or push a release tag unless the user asks.
- Releases are made from the default branch. There are no release branches.
- Where a project has continuous delivery, each commit that bumps the version is released when it lands, and a commit that doesn't bump it, such as a README fix, isn't. The project's `## Ways of working` section says whether it has this, and whether it's only planned.

## Go modules

In a Go module, from `v2.0.0` upwards the `go` command only accepts a version tag if the module path ends in the matching major version suffix, such as `/v2`. Without it, the tag is left out of `@latest` and version lists, and requesting it directly fails.

So a commit that bumps the major version to `v2` or later must also add the suffix to the module path in `go.mod`, and to every import path that uses it:

```text
module github.com/OWNER/REPO/v2
```

Reviewers check this in the pull request.

## Checklist

Before you decide a bump, check that:

- You looked at what the commit changes, not only its type.
- A breaking change is marked with `!` in the header, and its body starts with what breaks, why, who is affected and what to do instead.
- The bump follows the alpha, beta or `v1.0.0` rules, as the project's current version needs.
- A Go module moving to `v2` or later also changes its module path.
