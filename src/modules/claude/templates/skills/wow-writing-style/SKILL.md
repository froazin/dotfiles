---
name: wow-writing-style
description: "House writing style. Applies only when ways of working is on. Use whenever a task writes or edits prose for people or agents: a README.md, CONTRIBUTING.md, CLAUDE.md, a design doc or any doc in docs/, a GitHub wiki page, a Claude Code rule or skill, an issue or the body of a commit message or pull request description. Covers British English, tone, contractions, punctuation (no em dashes, no serial comma, no e.g. or i.e.), sentence-case headings, document structure, the 200-line limit, how to state facts and sources, placeholders for private values and writing triggers for agents."
---

# Writing style

The house style for everything written in a project: docs, READMEs, `CONTRIBUTING.md` files, wiki pages, `CLAUDE.md` files, rules and skills. Commit messages and pull requests have their own format (load the wow-commits and wow-pull-requests skills), but their bodies follow this style too. These are house defaults: where a project's `CLAUDE.md` sets its own style, such as American English, follow the project.

## Language

- Write in British English: `behaviour`, `licence` (the noun), `recognise`, `normalise`, `sanitise`. Keep names, quotes, code and URLs as they are, such as "MIT License" or a CSS `color`.
- Use plain words and short sentences, with one idea per sentence.
- Write instructions as commands to the reader: "Load the skill before you commit", not "The skill should be loaded before committing".
- Use the active voice, and say who does what: "GitHub appends the pull request number", not "the number is appended".
- Use contractions: `don't`, `isn't`, `it's`, `can't`.
- Write "for example" or "such as". Never write "e.g." or "i.e.".
- Don't use em dashes. Use a colon, brackets or a new sentence instead.
- Don't use a serial comma: "Docker, Podman and Buildah".
- Don't write "please", "simply", "just" or "easy".
- Spell out an abbreviation the first time a doc uses it, such as "pull request (PR)", unless every reader knows it, such as Git, URL or CI.
- Refer to people by role: users, maintainers, contributors, reviewers. Use "they" for anyone whose pronouns you don't know.
- In a project's files, state conventions as the project's own. Projects are shared, so never attribute them to one person, such as "the user's conventions", and never mention the ways of working or the `wow-*` skills unless the user asks.

## Structure

- Cover one topic per document. Name the file after the topic, in lowercase with hyphens, such as `commit-messages.md`.
- Start with a `#` title in sentence case, then one or two sentences that say what the doc covers and who it's for. GitHub wiki pages are the exception: they have no `#` title (load the wow-github-wiki skill).
- Use sentence case for every heading: "Branch names", not "Branch Names".
- Use `##` for sections and `###` for subsections. Don't skip a level.
- Keep each document under 200 lines, so agents don't truncate it when they read it. If one has to be longer, add a `## Contents` list of its sections straight after the intro. In a code repository, every doc in `docs/` and every `CLAUDE.md` has one, whatever its length (load the wow-repo-docs skill).
- Put the most-used material first: a quick reference before the detail, and a checklist at the end.
- State each fact in one place, and link to it from everywhere else that needs it. A rule copied into several docs drifts apart.
- End with a `## Sources` list of URLs when the doc relies on outside documentation or on observation.

## Markdown and diagrams

- Write GitHub Flavored Markdown: load the wow-markdown skill. It covers lists, code blocks, tables, links, alerts, collapsed sections and where each GitHub feature works.
- Draw diagrams in Mermaid: load the wow-diagrams skill.

## Facts and claims

- Describe only what exists. Describe anything planned as planned, such as "Releases will be made from `main`", never as though it's already there.
- Don't invent commands, flags, settings or file names. If a project has no build, test or lint command yet, say so.
- Say where a fact comes from when it isn't the official documentation. Mark it "observed" when you saw it happen, and "inferred" or "untested" when you didn't check. Quote the official docs when the exact words matter.
- Give exact values: versions, branch names, paths and environment variable names.
- Use placeholders for anything private or variable: `<vault>`, `<your-username>`, `OWNER/REPO`, `registry.example.com`. Never put real tokens, credentials, internal hostnames, account URLs or personal paths in anything public.

## Writing for agents

Claude agents read `CLAUDE.md` files, rules, skills and docs, as well as people.

- Say when to read or load something, as a trigger an agent can match: "**Load before you open a pull request.**"
- Say what to do when something is missing or fails, such as "If the skill isn't listed, read its `SKILL.md`."
- Prefer a short list of rules to prose. When the reason for a rule isn't obvious, give it in the same bullet.
- Use one name for a thing everywhere. If a doc calls a repository "Source", don't switch to "the code repo".
- Keep a skill's `description` to its triggers: the tasks it covers, in the words a request would use.
- Point to the document that holds a rule rather than copying the rule into a skill, a rule file or `CLAUDE.md`.

## Checklist

Before you finish a document, check that:

- It opens with a title and a sentence saying what it covers (no title on a wiki page).
- Headings are in sentence case and don't skip levels.
- Spelling is British, with no "e.g.", "i.e.", em dashes or serial commas.
- It passes the checklist in the wow-markdown skill, and every diagram the one in the wow-diagrams skill.
- Nothing planned is described as existing, and no command is invented.
- No private value appears in anything public.
- It's under 200 lines, or has a `## Contents` list. A doc in a code repository's `docs/`, or its `CLAUDE.md`, always has one.
