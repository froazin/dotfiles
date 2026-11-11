---
name: wow-versioning
description: "House Semantic Versioning rules for code repositories: how what a commit changes decides its type and a major, minor, patch or no bump; what counts as a breaking change; working out the next version with commitizen and a .cz.toml; pre-release versions before v1.0.0 and opt-in alpha, beta and rc tags; releases and tags made by CI with a v prefix; continuous delivery; urgent releases of dependency updates; and the Go module path suffix from v2. Use when ways of working is on and a task decides whether a change bumps the version, works out the next version, sets up or runs commitizen (cz bump), adds a .cz.toml, marks a breaking change, asks about or prepares a release or release tag, needs a dependency update released urgently, moves a project to v1.0.0 or moves a Go module to v2 or later."
---

# Versioning

How a commit changes a project's version, how the next version is worked out, how releases are made and what changes at `v1.0.0`. These are house defaults: where the project's `CLAUDE.md` says otherwise, follow the project (see the wow-core rule).

Only code repositories have versions. Commits in direct-commit repositories and GitHub wikis never change a version (the wow-contributing skill describes the kinds of repository). A project without releases says so in its `CLAUDE.md`. Its commits still follow these rules, so the history is right when releases start.

## Semantic Versioning

Projects use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`, such as `1.2.3`.

| Part | Example | A change to it means |
| --- | --- | --- |
| `MAJOR` | **1**.2.3 | Breaking changes, from `v1.0.0` |
| `MINOR` | 1.**2**.3 | New features and capabilities, and breaking changes before `v1.0.0` |
| `PATCH` | 1.2.**3** | Fixes, refactorings and performance changes |

## How a commit changes the version

What a commit changes decides its type, and commitizen works out the bump from the types (see [Work out the version with commitizen](#work-out-the-version-with-commitizen)). Start at the top and use the first row that matches:

| What the commit changes | Type | Bump |
| --- | --- | --- |
| Nothing in the source code, such as docs, CI, tests or development tooling | `docs`, `ci`, `test`, `chore` or similar, never with `!` | None |
| A dependency, even one in the build artifact | `chore(deps)`, or the tool's own type for a tool's commit | None: it ships with the next release. See [Urgent dependency updates](#urgent-dependency-updates) |
| The source code, in a breaking change | Any type, with `!` | Minor before `v1.0.0`, major from `v1.0.0` |
| The source code, adding a feature or capability users can use | `feat` | Minor |
| The source code in any other way: a fix, a refactoring or a performance change | `fix`, `refactor` or `perf` | Patch |

- **Source code** is code that's reflected in the final build artifact. CI configuration, tests, docs and development tooling aren't source code.
- **A breaking change** is a change to the source code that isn't backward compatible and that users get by default. Mark it with a `!` in the header, and start the body with what breaks, why, who is affected and what to do instead, whatever its type (load the wow-commits skill).
- A change that breaks only contributors, such as a renamed CI input or a new development toolchain, isn't a breaking change: a `!` would release an unchanged artifact. Say what breaks in the body instead.
- Code behind a feature flag, including a breaking change users can only opt in to, is typed by whether users can reach it. Load the wow-feature-flags skill.

## Before `v1.0.0`

Every version below `v1.0.0` is a pre-release: the project isn't considered stable, and anything can change.

- A breaking change bumps the minor version, whatever its type. A `fix(ipc)!:` commit at `v0.3.1` gives `v0.4.0`.
- A feature bumps the minor version too. A history of fixes alone stays at `0.0.x`, and the first `feat` gives `0.1.0`.
- The project moves to `v1.0.0` when the maintainer decides it's ready. See [Move to `v1.0.0`](#move-to-v100).

A project that needs to tell alpha, beta and release candidate versions apart says so in its `CLAUDE.md`. Only then, add a SemVer pre-release suffix to the version they lead up to, counting from 0: `v1.0.0-alpha.0`, `v1.0.0-beta.0`, `v1.0.0-rc.0`. commitizen adds the suffix with `--prerelease alpha`, `beta` or `rc` to the version the commits give. For one that leads up to `v1.0.0`, add `--increment MAJOR`, because no commit gives a major bump before `v1.0.0`.

## From `v1.0.0`

The project is considered stable:

- Every breaking change, including a breaking fix, bumps the major version.
- Breaking changes mustn't be hidden behind a feature flag.
- If a breaking change is ever absolutely necessary, the maintainer plans it at the time.

## Work out the version with commitizen

Projects work out the next version with [commitizen](https://commitizen-tools.github.io/commitizen/) (`cz`). Ubuntu packages it as `commitizen`. If `cz` isn't installed, work out the bump from the tables in this skill and tell the user which package provides it. Don't install it unless the user asks.

commitizen reads its settings from `.cz.toml` at the repository's root. Add one to a project that has none only when the user agrees:

```toml
[tool.commitizen]
name = "cz_conventional_commits"
version_provider = "scm"
version_scheme = "semver2"
tag_format = "v$version"
major_version_zero = true
```

- `version_provider = "scm"` reads the current version from the latest `v` tag, so no file holds a version.
- `version_scheme = "semver2"` writes pre-release versions the SemVer way, such as `1.0.0-beta.0`, rather than commitizen's default PEP 440 form, `1.0.0b0`.
- `major_version_zero = true` makes a breaking change a minor bump before `v1.0.0`. commitizen 4.11.0 keeps applying it at `1.x` (observed), so it comes out when the project moves to `v1.0.0`.

Print the next version, without the `v`, with `cz bump --get-next --yes`:

- Run it on an up-to-date default branch. On a feature branch it reads the branch's own commits, but the squashed PR title is what lands. For a PR, work out the bump from its title with the table in [How a commit changes the version](#how-a-commit-changes-the-version).
- It changes nothing. `--yes` answers the question commitizen asks when there's no tag yet: without it, the command waits for input (observed).
- When no commit since the latest tag calls for a bump, it prints `[NO_COMMITS_TO_BUMP]` and exits with code 21. When there are no commits since the tag at all, it prints `[NO_COMMITS_FOUND]` and exits with code 3. Either way, there's nothing to release. After a pre-release tag, such as `v1.0.0-alpha.0`, it prints the final version, `1.0.0`, even with no new commits.
- Never run `cz bump` without `--get-next`. It commits every modified tracked file with `git commit -a` before it tags. With `version_provider = "scm"` it has no file to change, so on a clean checkout that commit fails and it never tags. Releases are CI's job (see [Releases](#releases)).

commitizen reads the header and every line of the body, and takes the biggest bump any line asks for:

| A line that starts with | Bump before `v1.0.0` | Bump from `v1.0.0` |
| --- | --- | --- |
| Any type with `!` | Minor | Major |
| `feat` | Minor | Minor |
| `fix`, `perf` or `refactor` | Patch | Patch |
| Any other type, such as `docs`, `ci`, `test` or `chore` | None | None |

- A body line that starts like a header, such as `feat(cli): Add a flag`, bumps the version too. The wow-commits skill says how to avoid one.
- commitizen can't see what a commit changes, so the types have to say it.

## Releases

- The project's CI makes releases from the default branch: it works out the version with `cz bump --get-next --yes` and creates the tag with Git. Don't create or push a release tag yourself.
- Each tag is the version with a `v` prefix, such as `v1.0.2`.
- There are no release branches.
- Where a project has continuous delivery, each commit that bumps the version is released when it lands, and a commit that doesn't bump it, such as a README fix, isn't. The project's `CLAUDE.md` says whether it has this, and whether it's only planned.

### Move to `v1.0.0`

1. The maintainer decides the project is stable.
1. A PR removes `major_version_zero` from `.cz.toml`. It's a `chore`, so it doesn't bump the version.
1. Straight after it lands, before any other PR, the maintainer has CI tag `v1.0.0` by hand. Once the setting is gone, the next `!` commit would give `1.0.0` by itself, and a `feat` another `0.x` release.

### Urgent dependency updates

A dependency update doesn't bump the version, so it ships with the next release. When a fix in a dependency, such as a security fix, can't wait, and the user agrees:

1. **The PR is still open:** retitle it to `fix(deps):` with the rest of the tool's title, so it lands as a patch. This is the only time a tool's title is reworded. A tool's PR usually has one commit, and GitHub's merge box can offer that commit's header instead of the title, so check the header before merging, or set it with `gh pr merge --subject` (load the wow-pull-requests skill).
1. **It has already landed:** have CI cut a patch release by hand, such as with a workflow that tags the version `cz bump --get-next --yes --increment PATCH` prints on the default branch. If the project has no such workflow, suggest adding one.
1. **Last resort, when there's no such workflow:** reword the landed commit's header to `fix(deps):` and push the default branch with `git push --force-with-lease`. It needs permission to bypass the branch's protection, so only do it when the user asks, and only while the commit is still the latest on the default branch. It's the only exception to never force-pushing the default branch.

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
- A breaking change users get by default has `!` in the header, and its body starts with what breaks, why, who is affected and what to do instead. A change outside the source code has no `!`.
- Code behind a flag is typed as the wow-feature-flags skill says.
- You ran `cz bump` only with `--get-next`, on the default branch, and didn't create a release tag.
- A project that moves to `v1.0.0` removes `major_version_zero` from its `.cz.toml`.
- A Go module moving to `v2` or later also changes its module path.

## Sources

- https://semver.org/
- https://commitizen-tools.github.io/commitizen/
- https://github.com/commitizen-tools/commitizen
- https://go.dev/ref/mod
