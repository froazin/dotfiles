---
name: wow-versioning
description: "House Semantic Versioning rules for code repositories: how what a commit changes decides its type and a major, minor, patch or no bump; working out the next version with commitizen and a .cz.toml; the first release at v0.1.0 and the beta (0.x.y) stage before v1.0.0; breaking changes; release tags with a v prefix; continuous delivery; and the Go module path suffix from v2. Use when ways of working is on and a task decides whether a change bumps the version, works out the next version, sets up or runs commitizen (cz bump), marks a breaking change, creates or pushes a release tag, prepares a release, makes a first release, moves a project to v1.0.0 or moves a Go module to v2 or later."
---

# Versioning

How a commit changes a project's version, how the next version is worked out, how releases are tagged and what changes at `v1.0.0`. These are house defaults: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Only code repositories have versions. Commits in direct-commit repositories and GitHub wikis never change a version (the wow-contributing skill describes the kinds of repository). A project without releases says so in its `CLAUDE.md`. Its commits still follow these rules, so the history is right when releases start.

## Semantic Versioning

Projects use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`, such as `1.2.3`.

| Part | Example | A change to it means |
| --- | --- | --- |
| `MAJOR` | **1**.2.3 | Breaking changes, from `v1.0.0` |
| `MINOR` | 1.**2**.3 | New features and capabilities, and breaking changes before `v1.0.0` |
| `PATCH` | 1.2.**3** | Fixes, refactorings, performance changes and dependency updates that don't fit the other two |

## How a commit changes the version

What a commit changes decides the bump. Choose the commit's type to match it, because commitizen works out the version from the types (see [Work out the version with commitizen](#work-out-the-version-with-commitizen)). Start at the top and use the first row that matches:

| What the commit changes | Bump | Example |
| --- | --- | --- |
| Nothing in the source code, whatever it is. For example docs, CI or tests | None | `v1.4.2` stays `v1.4.2` |
| The source code, in a way that isn't backward compatible, from `v1.0.0` | Major | `v1.4.2` to `v2.0.0` |
| The source code, in a way that isn't backward compatible, before `v1.0.0` (beta), and not behind a flag that's off. Includes turning on a breaking change that was behind a flag | Minor | `v0.3.1` to `v0.4.0` |
| The source code, adding a feature or capability users can use (not behind a flag that's off). Includes turning on a feature that was behind a flag | Minor | `v1.4.2` to `v1.5.0` |
| The source code in any other way: a fix, a refactoring, a performance change, a dependency update that changes the build artifact, new code behind a flag that's off (even a breaking change in beta), or turning on a non-breaking fix that was behind a flag | Patch | `v1.4.2` to `v1.4.3` |

- **Source code** is code that's reflected in the final build artifact. CI configuration, tests and docs aren't source code.
- Choose the type by the content. A commit that doesn't touch the source code is `docs`, `ci`, `test` or `chore`, never `feat` or `fix`, even when it adds a doc page.
- A dependency update is a patch when it changes the build artifact, and no bump when it only affects tests or tooling.
- Mark every breaking change with a `!` in the header, and start the body with what breaks, why, who is affected and what to do instead, whatever its type (load the wow-commits skill).
- For flags, load the wow-feature-flags skill.

## Before the stable release

Every project's first release is `v0.1.0`. Before `v1.0.0`, the project is in beta and isn't considered stable:

| Stage | Versions | A breaking change | A new feature | Anything else |
| --- | --- | --- | --- | --- |
| Beta | `0.x.y`, from `v0.1.0` | Minor | Minor | Patch |

- There's no `0.0.x` stage. Don't release a version below `v0.1.0`.
- A breaking change to the source code bumps the minor version, whatever its type. A `fix(ipc)!:` commit at `v0.3.1` gives `v0.4.0`.
- A breaking change hidden behind a flag that's off is a patch while it's hidden. The commit that turns the flag on is a minor bump.
- The project moves to `v1.0.0` when the maintainer decides it's ready.

## From `v1.0.0`

The project is considered stable:

- Every breaking change to the source code, including a breaking fix, bumps the major version.
- Breaking changes mustn't be hidden behind a feature flag.
- If a breaking change is ever absolutely necessary, the maintainer plans it at the time.

## Work out the version with commitizen

Projects work out the next version with [commitizen](https://commitizen-tools.github.io/commitizen/) (`cz`), which Ubuntu packages: `sudo apt-get install commitizen`. It reads the Conventional Commit headers since the latest tag. Put its settings in `.cz.toml` at the repository's root:

```toml
[tool.commitizen]
name = "cz_conventional_commits"
version_provider = "scm"
tag_format = "v$version"
major_version_zero = true
```

- `version_provider = "scm"` reads the current version from the latest `v` tag, so no file holds a version.
- `major_version_zero = true` makes a breaking change a minor bump before `v1.0.0`. Remove it in the change that moves the project to `v1.0.0`: commitizen 4.11.0 keeps applying it at `1.x` (observed).
- Print the next version, without the `v`, with `cz bump --get-next --yes --allow-no-commit`. It changes nothing. `--yes` answers the question commitizen asks when there's no tag yet, and without it the command waits for input (observed). `--allow-no-commit` gives a patch when no commit calls for a bump.
- Don't run `cz bump` without `--get-next` unless the user asks: it creates a tag.

commitizen bumps by the headers alone:

| Header | Bump before `v1.0.0` | Bump from `v1.0.0` |
| --- | --- | --- |
| Any type with `!` | Minor | Major |
| `feat` | Minor | Minor |
| `fix`, `perf` or `refactor` | Patch | Patch |
| Any other type, such as `docs`, `ci`, `test` or `chore` | None | None |

- With no tags, it counts from `0.0.0`, so a history with a `feat` gives `0.1.0` (observed). When it gives a `0.0.x` version for the first release, release `v0.1.0` instead.
- It can't see what a commit changes, so the types have to say it. Where the table above gives a different bump from the type, such as new code behind a flag that's off, raise it with the user before the release.

## Tags and releases

- Tag each release in Git with its version and a `v` prefix, such as `v1.0.2`. Always include the `v`.
- Tags are signed, like commits. Don't create or push a release tag unless the user asks.
- Releases are made from the default branch. There are no release branches.
- Where a project has continuous delivery, each commit that bumps the version is released when it lands, and a commit that doesn't bump it, such as a README fix, isn't. The project's `CLAUDE.md` says whether it has this, and whether it's only planned.

## Go modules

In a Go module, from `v2.0.0` upwards the `go` command only accepts a version tag if the module path ends in the matching major version suffix, such as `/v2`. Without it, the tag is left out of `@latest` and version lists, and requesting it directly fails.

So a commit that bumps the major version to `v2` or later must also add the suffix to the module path in `go.mod`, and to every import path that uses it:

```text
module github.com/OWNER/REPO/v2
```

Reviewers check this in the pull request.

## Checklist

Before you decide a bump, check that:

- You looked at what the commit changes, and its type gives the bump the table asks for.
- A breaking change is marked with `!` in the header, and its body starts with what breaks, why, who is affected and what to do instead.
- The bump follows the beta or `v1.0.0` rules, as the project's current version needs, and no release is below `v0.1.0`.
- A project that moves to `v1.0.0` removes `major_version_zero` from its `.cz.toml`.
- A Go module moving to `v2` or later also changes its module path.
