---
name: validate-wsl-user-data
description: Render and validate the WSL cloud-init user-data (src/wsl/ubuntu.user-data) against mock meta-data. Use after any change to src/wsl/ubuntu.user-data or src/wsl/ubuntu.meta-data, before saying a change works.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/validate.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/validate.sh)
---

# Validate the WSL user-data

`src/wsl/ubuntu.user-data` is a Jinja template (`## template: jinja`), so
running `cloud-init schema` on the raw file proves nothing. Run:

```sh
${CLAUDE_SKILL_DIR}/scripts/validate.sh            # defaults to src/wsl/ubuntu.user-data
${CLAUDE_SKILL_DIR}/scripts/validate.sh path/to/file
```

It renders the template with `cloud-init devel render` against a set of mock
`ds.meta_data` cases and checks each result:

| Case | Proves |
| ---- | ------ |
| `full` | every key renders; user, `.gitconfig` and GitHub workspace dir appear |
| `empty-values`, `no-meta-data` | nothing user-specific renders, YAML stays valid |
| `hostile-name` | `"`, `\`, `#`, `;`, `'` and `{{ }}` in `git_name` read back exactly through `git config` |
| `legacy-noreply`, `plain-email`, `path-traversal` | the `~/workspaces/github.com/<owner>` extraction only accepts GitHub noreply addresses with a safe owner name |

It also runs `cloud-init schema` on every render, shellchecks the embedded
`/usr/local/bin/start`, and fails if a concrete `/mnt/c/Users/<name>/` path
appears in the template.

Exit 0 means every case passed; any `FAIL:` line names the case and what broke.

When adding a meta-data key or a new conditional block, add a case for it to
the Python table at the top of the script, including the "key unset" side.

This does not replace a real first boot. Only an end-to-end run on a
throwaway instance (see the README) exercises the WSL datasource, the OOBE and
the package installs, and it writes to the user's Windows profile, so ask
before doing it.
