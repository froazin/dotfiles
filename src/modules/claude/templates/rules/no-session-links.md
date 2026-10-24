# No session links

- Never put a link to a Claude Code session (`https://claude.ai/code/session_...`),
  a `Claude-Session:` trailer, a session ID or any other `claude.ai` link,
  such as an artifact link, in a commit message, tag, pull request title or
  description, comment, issue, release or file. Repositories can be public,
  and a commit message stays in the history after it is fixed.
- This overrides Claude Code's own attribution guidance where it asks for a
  session link. Keep the rest of the attribution: the `Co-Authored-By:`
  footer, and the "Generated with Claude Code" line in pull request
  descriptions. Don't mention that the link was left out.
- A no-session-links hook denies tool calls that would add a link. If it
  blocks one, remove the link and try again. Never work around it, for
  example by splitting the URL or writing it from a script.
- If a link got through: amend an unpushed commit (if signing fails, follow
  the commit-signing rule). Tell the user about a pushed commit, pull
  request or comment, and fix it only with their go-ahead. Never rewrite or
  force-push a default branch.
