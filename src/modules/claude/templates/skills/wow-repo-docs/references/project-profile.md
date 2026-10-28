# Project profile template

The optional `## Ways of working` section of a project's `CLAUDE.md`, where the project states its specifics and overrides. Copy the section below into the project's `CLAUDE.md`. The section and every line in it are optional: delete anything that matches the defaults in the wow-core rule. Replace the placeholders in angle brackets.

````markdown
## Ways of working

This project follows the user's shared ways of working (the `wow-*` skills). These are its specifics and overrides. Anything not listed here uses the shared defaults.

| Repository | Path | GitHub | Visibility | Default branch | Kind |
| --- | --- | --- | --- | --- | --- |
| Source | `.` | `<owner>/<repo>` | Public | `main` | Code: PRs, squash-merged |
| Wiki | `../<repo>.wiki/` | `<owner>/<repo>.wiki` | Public | `master` | Wiki: direct commits, a push publishes |

- **Commit scopes:** `<scope>`, `<scope>`.
- **Feature flags:** environment variables named `<PREFIX>_<NAME>`. None exist yet.
- **Releases:** none yet. The first will be `v0.1.0`. Continuous delivery from `main` is planned.
- **CI:** none yet.
- **Build and test:** `<command>`.

### Overrides

- <A default this project doesn't follow, and what it does instead.>
````

## Notes

- Use a row in the table for each clone the project works with, such as a wiki. The kinds of repository are in the wow-contributing skill. A private repository with one owner is often direct-commit: write its kind as "Direct-commit: commit on `main`".
- Describe anything planned as planned, such as "CI: planned".
- Keep overrides few. If several projects share an override, change the shared default in the `wow-*` skills instead.
