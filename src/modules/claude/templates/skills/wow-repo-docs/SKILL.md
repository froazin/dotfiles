---
name: wow-repo-docs
description: "Where a project's docs belong and how to write a code repository's docs. Applies only when ways of working is on. Use whenever a task writes, changes or trims a design doc in docs/ or a code repository's README.md, CLAUDE.md or CONTRIBUTING.md; decides whether a doc belongs in docs/, the GitHub wiki, the README, CONTRIBUTING.md, CLAUDE.md or a code comment; decides how much a doc should say; updates docs alongside a code change; or adds or edits the optional \"## Contributing\" section (project profile) in a project's CLAUDE.md, such as its repositories table, commit scopes, feature flag prefix, releases or CI, or renames an older \"## Ways of working\" section."
---

# Repository docs

Where each kind of documentation lives in a project, and how to write the docs in a code repository: its `docs/` folder, `README.md`, `CLAUDE.md` and `CONTRIBUTING.md`. **Load before you write or change any of them, or decide where a doc belongs.** Source means the project's code repository. These are house defaults, such as user docs in the wiki: where a project's `CLAUDE.md` says otherwise, follow the project.

## Where docs go

| Doc | Lives in | For | Holds |
| --- | --- | --- | --- |
| User docs | The project's GitHub wiki | People who use the project | Installing, configuring, using and troubleshooting it. Load the wow-github-wiki skill |
| `README.md` | Source's root | Users first, then engineers | A pointer to the wiki, then the engineering entry point |
| Design docs | Source's `docs/` | Engineers and agents who change the code | High-level design: how the parts fit together and why |
| `CONTRIBUTING.md` | Source's root | Contributors | Reporting a problem, proposing a change, building, testing and what CI runs |
| `CLAUDE.md` | Source's root | Claude agents | The index: layout, conventions and which design doc to read before changing each part |
| Code comments | The code | Engineers reading that code | What one function, type or package doesn't make obvious |

- Put each fact in one of these, and link to it from the others.
- Never put user docs in `docs/`, or design, build or test docs in the wiki. `docs/` is never a copy of the wiki.
- Shared practices, such as commit messages and branching, live in the `wow-*` skills, not in a project's docs. `CONTRIBUTING.md` summarises them for external contributors, as the project's own rules.
- Never mention the ways of working, the `wow-*` skills or a `.wow` marker in a project's docs, unless the user asks. Other contributors may not have them (the wow-core rule).
- If the project has no wiki, ask the user where user docs go before you write any.

## Design docs

### What a design doc is for

A design doc gives an engineer or agent the picture the code can't: what the parts are for, how they fit together and why they're built that way. It leaves the detail to the code.

Cover only what applies, briefly. These are topics, not headings: use the sections in [Shape of a design doc](#shape-of-a-design-doc).

- **Purpose and boundaries:** what the part is for, what it deliberately doesn't do and where it sits among the other parts. This goes in the intro.
- **How it fits together:** the main flow of data or control between components, not between functions.
- **Decisions:** the choices that shaped it, the alternatives rejected and why.
- **Constraints:** what would break if changed carelessly and the code doesn't make obvious, such as an ordering requirement, a platform quirk, untrusted input or something that must never be logged or sent. Include known gaps, so a reader can tell a gap from a bug: the code can't show what it doesn't do.

Write a design doc only for a part whose design isn't clear from its code. A small or obvious part needs none: if one already has a doc, shrink or remove it, and fix the links to it.

### Leave it out

Before you add a sentence, ask whether a capable engineer reading the code would miss it. If not, cut it.

- **What the code says:** walkthroughs of files or functions, and lists of options, flags, settings, defaults, error messages, log lines or test cases. Link to the file instead.
- **What readers already know:** how a standard tool, language feature or protocol works, and general good practice.
- **Process:** commit, branch, pull request (PR), review, release and writing practice, and how to run the checks. Where a project differs from common practice, the difference goes in its `CLAUDE.md` or `CONTRIBUTING.md`, not `docs/`. A doc about the project's own CI or release automation describes how that automation is built, like any other component.

Keep design docs short. A doc that grows long is describing the code: cut detail before you split it.

### Diagrams, links and code

- Add a Mermaid diagram where a structure or flow is easier to see than to read, usually one at the level of components. Load the wow-diagrams skill.
- Link to the code with relative paths, such as `[store.go](../internal/store/store.go)`, and put identifiers in code spans.
- Most design docs need no `## Sources`. Cite outside docs only for a claim a reader would need to check, not for how a common tool works.
- Link to the code rather than copying it: excerpts drift. Show a short example only for a contract between components that no one file shows, such as a file format.

### Keep docs in step with the code

- `docs/` is versioned with the code, so a doc describes the code on the same branch. Update it in the same PR as a change that makes it wrong.
- Describe anything not built yet as planned. A doc for a proposed design says so in its intro.
- A docs-only change doesn't bump the version (load the wow-versioning skill).

### Files and names

- Cover one topic per file. Name it after the topic, in lowercase with hyphens, such as `docs/error-handling.md`.
- Start flat. When several docs cover one area, move them into a subfolder with an `overview.md` that links to the rest.
- Put images that aren't diagrams, such as screenshots, in `docs/images/`.
- Write in the house style and GitHub Flavored Markdown (load the wow-writing-style and wow-markdown skills).

### Shape of a design doc

```markdown
# <Topic>

<What this part is for and where it sits, in one or two sentences.>

## How it fits together

## Decisions

## Constraints
```

Leave out a section with nothing to say. Add a `###` subsection only where a topic is too big for its section.

## README.md

1. A `#` title, and a one-line summary of what the project is.
1. **If the project has a wiki:** a short section for users, straight after the summary. Say what the project does for them, and link to the wiki and its main pages with absolute URLs, such as `https://github.com/OWNER/REPO/wiki/Installation`. Installation and usage steps live in the wiki, not here.
1. **The rest is for engineers:** what the code is and how it's built at a high level, and links to each design doc in `docs/`, to `CONTRIBUTING.md` and to the licence. Add an architecture diagram if the parts are easier to see than to read.

Don't copy `CLAUDE.md`'s layout map into the README. Describe the parts at the level of the architecture, and link to the design docs.

## CLAUDE.md

1. A `#` title: the project's name.
1. One or two sentences that say what the code is.
1. `## Layout`: each folder or package and what it holds and, where it has one, the design doc to read before you change it, written as a trigger, such as `` Before you change `internal/store/`, read [docs/store.md](docs/store.md). ``
1. `## Conventions`: rules for the code that an agent must follow and couldn't work out from the code, such as which dependencies are allowed. Link to `CONTRIBUTING.md` for build and test commands rather than copying them.
1. `## Contributing`: the optional project profile, with the project's repositories, commit scopes, releases and CI. Copy it from [references/project-profile.md](references/project-profile.md).

`CLAUDE.md` holds no design of its own. It points to `docs/`.

## CONTRIBUTING.md

- It's written for external contributors, and it's where the project documents how to build and test the code and what CI runs. Internal contributors use those facts too, though it ranks last for internal work (the wow-core rule sets which guidance wins).
- Cover reporting a problem, proposing a change, building, testing (including tests that need a special environment), CI and a summary of the commit, branch and PR rules, stated as the project's own.
- Link to `docs/` for design. Don't explain the design in `CONTRIBUTING.md`.

## Checklist

Before you finish a change to a code repository's docs, check that:

- Each fact is in the right place from [Where docs go](#where-docs-go), and nowhere else.
- Each design doc covers the design at a high level, and leaves out process, what the code says and what readers already know.
- The docs match the code on the branch, and anything planned is described as planned.
- The README sends users to the wiki first, if there is one.
- `CLAUDE.md`'s Layout names the design doc for every part that has one.
- No doc mentions the ways of working or the `wow-*` skills, or says whose conventions the project follows.
