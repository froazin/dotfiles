# Commit signing

- Git commits and tags on this machine are signed with the user's own key,
  and signing can need the user to approve a prompt in person (for example
  1Password with Windows Hello). When signing fails or times out, the user is
  away from their computer.
- When a commit, merge, rebase, cherry-pick, revert, am or tag fails to sign,
  stop. Do not retry it, and do not bypass, disable or redirect signing:
  no `--no-gpg-sign`, `--no-sign`, `-c commit.gpgsign=...`, `GIT_CONFIG_*`
  or `HOME` overrides, config edits, aliases or plumbing such as
  `commit-tree`. Do not offer an unsigned commit as an alternative.
- Instead, end the turn and tell the user that commit signing failed and
  needs them back at their computer. Say what is still uncommitted, and any
  half-finished merge, rebase, cherry-pick, revert or am state left behind.
- No hook enforces this on this machine, so it rests on you alone: when in
  doubt about whether a command would get round signing, don't run it, and
  ask.
