# Project profile template

The optional `## Contributing` section of a project's `CLAUDE.md`, where the project states how changes land: its repositories, commit scopes, feature flags, releases and CI. Copy the section below into the project's `CLAUDE.md`. The section and every line in it are optional: delete anything that matches the defaults in the wow-core rule. Replace the placeholders in angle brackets.

````markdown
## Contributing

| Repository | Path | GitHub | Visibility | Default branch | Kind |
| --- | --- | --- | --- | --- | --- |
| Source | `.` | `<owner>/<repo>` | Public | `main` | Code: PRs, squash-merged |
| Wiki | `../<repo>.wiki/` | `<owner>/<repo>.wiki` | Public | `master` | Wiki: direct commits, a push publishes |

- **Commit scopes:** `<scope>`, `<scope>`.
- **Feature flags:** environment variables named `<PREFIX>_<NAME>`. None exist yet.
- **Releases:** none yet. The first will be `v0.1.0`. Continuous delivery from `main` is planned.
- **CI:** none yet.
- **Build and test:** `<command>`.
- <A practice this project follows where it differs from the defaults, and why.>
````

## Notes

- The section is read by every contributor's agent, and most won't have the `wow-*` skills. Write each line as the project's own convention. Don't mention the ways of working, the skills or a `.wow` marker, and don't say whose conventions they are.
- Use a row in the table for each clone the project works with, such as a wiki. The kinds of repository are in the wow-contributing skill. A private repository with one owner is often direct-commit: write its kind as "Direct-commit: commit on `main`".
- Describe anything planned as planned, such as "CI: planned".
- State a difference from the defaults as a plain fact, such as "User docs live in `README.md`, not a wiki, because GitHub Marketplace shows an action's README." Don't label it an override.
- Keep those differences few. If several projects share one, change the shared default in the `wow-*` skills instead.
- A project that already has a `## Ways of working` section keeps working, because the skills follow the project's `CLAUDE.md` under any heading. When you next edit it, rename it to `## Contributing` and remove any mention of the skills, unless the user asks you to keep it.
