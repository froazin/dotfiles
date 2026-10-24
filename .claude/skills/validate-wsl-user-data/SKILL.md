---
name: validate-wsl-user-data
description: Render and validate the WSL cloud-init user-data (src/wsl/Ubuntu-26.04.user-data) against mock meta-data. Use after any change to src/wsl/Ubuntu-26.04.user-data or src/wsl/Ubuntu-26.04.meta-data, before saying a change works.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/validate.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/validate.sh)
---

# Validate the WSL user-data

`src/wsl/Ubuntu-26.04.user-data` is a Jinja template (`## template: jinja`), so
running `cloud-init schema` on the raw file proves nothing. Run:

```sh
${CLAUDE_SKILL_DIR}/scripts/validate.sh            # defaults to src/wsl/Ubuntu-26.04.user-data
${CLAUDE_SKILL_DIR}/scripts/validate.sh path/to/file  # with Ubuntu-26.04.meta-data beside it
${CLAUDE_SKILL_DIR}/scripts/validate.sh path/to/user-data path/to/meta-data
```

It renders the template with `cloud-init devel render` against a set of mock
`ds.meta_data` cases and checks each result:

| Case | Proves |
| ---- | ------ |
| `full` | every key renders; user, `.gitconfig`, `allowed_signers`, the ways-of-working config and GitHub workspace dir appear |
| `empty-values`, `no-meta-data` | nothing user-specific renders, YAML stays valid |
| `hostile-name` | `"`, `\`, `#`, `;`, `'` and `{{ }}` in `git_name` read back exactly through `git config` |
| `legacy-noreply`, `plain-email`, `path-traversal` | the `~/workspaces/github.com/<owner>` extraction only accepts GitHub noreply addresses with a safe owner name |
| `shipped-meta-data` | the repo's `Ubuntu-26.04.meta-data` template parses and its `vscode_extensions` install |
| `extensions-string` | a comma/space-separated `vscode_extensions` string installs each ID |
| `extensions-hostile` | only `publisher.name` IDs reach the shell; every other entry is reported with `printf`, ASCII-escaped, including non-BMP characters and backslashes |
| `extensions-mapping`, `extensions-number`, `extensions-no-user` | other types install nothing, and nothing installs without a user |
| `wow-padded`, `wow-multiline`, `wow-space`, `wow-list`, `wow-unicode`, `wow-no-user` | a trimmed one-word ASCII `ways_of_working` is written to the user's deferred `~/.config/ways-of-working/repo`; anything else is reported with `printf`, ASCII-escaped, and nothing is written without a user |
| `signingkey-ecdsa` | a `key::`-prefixed ECDSA key is trusted for `git_email` |
| `signingkey-no-email`, `signingkey-odd-email`, `signingkey-unicode-email` | a whitespace-padded key without `git_email`, or with one unsafe as a principal, is trusted for any identity (`*`), and `user.signingkey` is trimmed so git still reads it as a literal key |
| `signingkey-path`, `signingkey-bare-ecdsa`, `signingkey-hostile`, `signingkey-unknown-type`, `signingkey-bad-type`, `signingkey-unicode-type`, `signingkey-unicode-data`, `signingkey-type-only`, `signingkey-list`, `signingkey-no-user` | only a key git reads as literal (`key::` or `ssh-`) with a valid `<type> <base64>` gets an `allowed_signers` file and `gpg.ssh.allowedSignersFile`, and only with a user; `gpg.ssh.program` is kept without one |

Every case also checks one extension install per expected ID, run as the
user; that `podman.socket` is enabled with `systemctl --global` before the
first `runuser -l` starts the user's systemd manager, while root gets the
system socket and a `ConditionUser=!root` drop-in instead; and that cloud-init can
write the whole runcmd out as a UTF-8 script. Where an `allowed_signers` file
is expected, it signs a message with a throwaway key and checks that
`ssh-keygen` finds the expected principal and verifies it, as git does, but
not outside the `git` namespace.

It also runs `cloud-init schema` on every render, shellchecks the embedded
`/usr/local/bin/start`, and fails if a concrete `/mnt/c/Users/<name>/` path
appears in the template.

Exit 0 means every case passed; any `FAIL:` line names the case and what broke.
Exit 2 means it could not run: a missing tool, user-data or meta-data, or a
meta-data template that does not parse.

When adding a meta-data key or a new conditional block, add a case for it to
the Python table at the top of the script, including the "key unset" side.

This does not replace a real first boot. Only an end-to-end run on a
throwaway instance (see the README) exercises the WSL datasource, the OOBE and
the package installs, and it writes to the user's Windows profile, so ask
before doing it.
