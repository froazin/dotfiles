# Review instructions

What CI's Claude code review flags on pull requests (PRs) in this repository, at what severity and what it skips. Rules for all work are in `CLAUDE.md` and `.claude/rules/`, and a change that breaks one of them is a finding. This file adds only what's specific to reviews.

Judge `src/` as what ships: people copy these dotfiles, and the installer writes them into their home and root's, where the zsh config runs in every shell and the claude module's hooks run on Claude Code's tool calls. Judge the tests, the dev tooling and the workflows by whether they still check and release the dotfiles correctly, not by the standards of the dotfiles themselves.

## What Important means here

Mark a finding Important only when the change would do one of these:

- Make `src/install.sh` or a module fail, stop early or exit non-zero where `CLAUDE.md`'s dependency grading says it mustn't: a module is skipped only when its own command is missing, a missing soft dependency fails the module but still installs the config, and a missing optional one only warns.
- Overwrite or lose a user's own config, such as replacing `~/.claude/settings.json` or `keybindings.json` instead of merging into them, following a symbolic link the installer leaves alone, or writing outside the home it's installing into. `docs/installer.md` and `docs/claude/overview.md` describe what each module may touch.
- Make a zsh template print, fail or hang on shell startup, such as a tool used without a runtime guard, or do something as root that `.claude/rules/zsh-module.md` says must not run as root.
- Let the commit-signing guard allow a way round signing that it denies today, let the no-session-links hook let a session link through, or make either block a call it shouldn't. A hook that errors must still exit 0 with no output, and exit 2 only for what it exists to block. `docs/claude/commit-signing-guard.md` and `docs/claude/no-session-links.md` describe them.
- Make an installed hook depend on something a fresh install may lack, such as `jq`, `python3` or a PyPI package, other than through a wrapper that exits 0 when it's missing, or source `logging.sh` or `common.sh`. `.claude/rules/posix-sh.md` and `.claude/rules/python.md` have the rules.
- Make a `wow-*` skill or rule contradict another, tell an agent to do something unsafe, such as pushing, tagging, merging or force-pushing without the user asking, or tell it to mention the skills or a `.wow` marker in a project's files. `.claude/rules/wow-content.md` has the rules.
- Put identifying data into the repository, such as a real name, email, username, signing key, hostname or `/mnt/c/Users/<name>/` path. The repository is public.
- Add a tool a module or template depends on without keeping the three dependency lists in step, as `CLAUDE.md` says.
- Make the README's install steps wrong, or make a design doc, the README, `CLAUDE.md` or this file say something about the code that's false after the change, so that someone following it would do the wrong thing.
- Make CI or the release workflow skip a check that the change needs, such as a `!` pattern added to `paths` in `.github/workflows/ci.yml` or `.github/workflows/release.yml` that skips a path the checks read or that gets installed. Drop or narrow a check the `checks` job runs, or let a job run when one it needs failed. `docs/ci.md` and `docs/releases.md` describe how they should work.
- Give a job other than `release` in `release.yml` a token that can write, other than the permissions its `ci` job allows for CI's code review, or let the `release` job check out or run the repository's code. `docs/releases.md` describes why.
- Widen what the Claude run in CI can do, such as its `permissions`, its `github_token`, its `--allowedTools` or its `--disallowedTools`, past what the "Security" section of `docs/ci.md` allows, even when the change updates that doc too. Give `CLAUDE_CODE_OAUTH_TOKEN`, or a token that can write, to a step that runs the PR's code, or pass secrets to `ci.yml` from the release workflow.
- Use an action without pinning it to a full commit SHA with its version in a comment, pin one to a release less than 7 days old, or shorten the 7-day Dependabot cooldown.

Naming, structure, refactoring ideas, comments and doc wording are Nits at most.

## Pre-existing issues

Don't report an issue that was there before this PR, however serious. It's out of scope for the PR.

## Cap the Nits

Every comment must be resolved before the PR can merge, so report Nits sparingly: at most three per review, and only ones likely to mislead a maintainer or a Claude agent working from the docs. On a review after new commits, report Nits only on code those commits change. CI's code review posts none from the fourth review on a PR, as the "Code review" section of `docs/ci.md` says.

## Don't report

- Anything ShellCheck, shfmt, `zsh -n`, ruff, pyright or pytest reports, or a failure of the scratch install. CI runs them before the review.
- The PR's title and description.
- A limit that a design doc's Limits section records, unless the change makes it worse.
- An issue that a resolved review thread on the PR already raises, whatever its replies say. Resolving a thread settles it.

## Always check

These are the rules that no tool, test or check enforces.

### The installer and modules

- Installer scripts are POSIX `sh`, log with `log` and collect errors in a flag rather than stopping, as `.claude/rules/posix-sh.md` says. ShellCheck catches only some of this.
- A new file a module installs is written with `install_file`, so a symbolic link or an unchanged file is left alone.
- A change to what a module installs, or to how, updates its design doc in the same PR.

### The zsh config

- A new integration is guarded with `(( $+commands[tool] ))` or a file test, and prints nothing when the tool is missing.
- A setting goes in the drop-in whose topic it belongs to, and anything that registers ZLE widgets loads before `90-plugins.zsh`.

### The claude module

- A fix to the commit-signing guard or the no-session-links hook comes with a test case, as `.claude/rules/python.md` says. A missing case is a Nit.
- A new or changed `wow-*` fact is stated in one place, and other skills point to it by name ("load the wow-X skill"), never by a link.

### CI

- A new job in `ci.yml` or `release.yml` needs the jobs whose results it depends on, so it doesn't run after one of them failed.
- A new path that the checks read, or that gets installed, isn't skipped by a `!` pattern in `paths` in `ci.yml` or `release.yml`, and the two lists stay the same.
- A change to this file's severities, its Nit cap or what it says about pre-existing issues also changes the code review's prompt in `.github/workflows/ci.yml`, and the other way round.

## Evidence

- Cite a `file:line` in this repository for every claim about behaviour. Don't infer behaviour from a name.
- A review doesn't run the installer, zsh or the hooks. Claim that something would fail only when the code, a test or a design doc shows why.
