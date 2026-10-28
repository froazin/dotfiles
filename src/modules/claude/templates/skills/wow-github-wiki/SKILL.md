---
name: wow-github-wiki
description: "House rules for GitHub wiki pages, links, markup, sidebars, footers and publishing. Use when ways of working is on and a task creates, edits, renames, moves or deletes anything in a GitHub wiki clone (a <repo>.wiki/ folder), including Home.md, _Sidebar.md, _Footer.md and images; adds or fixes a wiki link ([[Link text|Page-Name]]), a heading anchor or a link into the wiki from the code repository; adds an alert, table, code block, Mermaid diagram or image to a wiki page; converts GitBook or other Markdown docs to GitHub wiki format; or clones, commits, pushes, publishes or reverts wiki changes."
---

# GitHub wiki

How to write, edit, rename, delete and publish pages in a project's GitHub wiki. **Read before you create, edit, rename or delete anything in a wiki clone, including `_Sidebar.md`, `_Footer.md` and images, and before you commit or push wiki changes.**

These are house defaults. A project's own `CLAUDE.md` can override them.

## Placeholders

| Placeholder | Means | Usually |
| --- | --- | --- |
| `OWNER/REPO` | The GitHub repository the wiki belongs to | Given in the `## Ways of working` section of the project's `CLAUDE.md`, or by `git remote -v` |
| Source | That repository: the project's code | |
| `<source>/` | The local clone of Source | The project root |
| `<wiki>/` | The local clone of the wiki, `https://github.com/OWNER/REPO.wiki.git` | `<repo>.wiki/`, next to `<source>/` |

## How a wiki works

- A wiki is a separate Git repository from Source. Its pages are published at `https://github.com/OWNER/REPO/wiki` as soon as a commit is pushed to `master`.
- The default branch is `master`, not `main`. Only commits on `master` are published.
- A wiki has no pull requests. Commit directly on `master`, and treat the user's go-ahead before a push as the review.
- The layout is flat. Every page is a uniquely named `.md` file at the root of `<wiki>/`. Don't create subdirectories for pages.
- `Home.md` is the landing page, served at `/OWNER/REPO/wiki`.
- `_Sidebar.md` holds the navigation, and `_Footer.md` the footer shown on every page.
- Images go in `<wiki>/images/`.

Before you change anything, read `<wiki>/_Sidebar.md` (if it exists) and run `ls <wiki>` to see which pages exist. If the clone is missing, clone it first (see [Git workflow](references/git-workflow.md#cloning)).

## What belongs in a wiki

- A wiki is for people who use the project. Write only user-facing documentation there.
- Don't put contributor, development or design docs in a wiki. Load the wow-repo-docs skill for where each kind of doc goes.
- Never put `.claude/`, `CLAUDE.md` or any other Markdown file that isn't meant to be a page in the wiki repository. GitHub publishes every `.md` file in it as a page, including files in subdirectories.
- Document only behaviour that exists on Source's default branch, not on a branch that hasn't merged, because a push publishes straight away. Describe anything planned as planned.
- Use placeholders such as `<vault>` and `registry.example.com` in examples. Never use real credentials, tokens, account URLs, internal hostnames or private identifiers.
- Write GitHub Flavored Markdown that GitHub's wiki renders, in the house style, with diagrams in Mermaid. Load the wow-markdown, wow-writing-style and wow-diagrams skills for those rules.
- Don't use GitBook syntax (`{% ... %}` blocks, `SUMMARY.md`, `.gitbook.yaml`, front matter) or any other site generator's syntax.

## Quick reference

### Titles and filenames

- The filename is the title. GitHub shows hyphens as spaces and keeps the filename's case: `Getting-started.md` is displayed as "Getting started" at `/wiki/Getting-started`.
- Name files in sentence case, with ASCII hyphens between words and a `.md` extension. Don't put a literal hyphen inside a title word: GitHub would show it as a space.
- Never use `\ / : * ? " < > |` in a filename.
- Every basename must be unique across the wiki. Page lookup ignores case, so names that differ only in case also clash.

### Page content

- No `#` H1 anywhere. GitHub renders the title above the content, so a leading `# Title` shows the title twice. Start with an intro paragraph, use `##` for sections and `###` for subsections.
- No YAML front matter. Put anything a description would have said into the intro sentence.
- Use `-` for bullets, fenced code blocks with a language (`bash`, `text`) and GFM tables.
- No in-page table of contents. GitHub builds a heading outline for each page in the sidebar's Pages box.

### Links

The page names below show the syntax only. Check `ls <wiki>` for the pages that actually exist.

| Target | Write | Example |
| --- | --- | --- |
| Another wiki page | `[[Link text\|Page-Name]]` | `[[Configure the tool\|Configuration]]` |
| A heading on another page | `[[Link text\|Page-Name#slug]]` | `[[Some heading\|Troubleshooting#some-heading]]` |
| A page, with its title as the link text | `[[Page name]]` | `[[Home]]`, `[[Installation]]` |
| A heading on the same page | `[text](#slug)` | `[Checklist](#checklist)` |
| A file in Source | absolute URL | `[LICENSE](https://github.com/OWNER/REPO/blob/main/LICENSE)` |
| An external site | `[text](https://...)` | `[Semantic Versioning](https://semver.org/)` |

- Inside `[[...]]`, the link text comes first and the page second. The page-first order shown in GitHub's own docs breaks in `.md` pages (observed).
- In the bare form, write the title with spaces. GitHub matches spaces to hyphens, but shows the text as written.
- Never link to `Page-Name.md`. That URL redirects to the raw Markdown file.
- Anchor slugs are lowercase, with spaces as hyphens and punctuation removed. Repeated headings get `-1`, `-2`. Always write anchors in lowercase.
- Files in Source, such as its `README.md`, can't use `[[...]]`. They link to a page by its absolute URL, `https://github.com/OWNER/REPO/wiki/Page-Name`.

### Alerts

GitHub alerts render on wiki pages (observed: GitHub's docs don't mention wikis for alerts). Use `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]`:

```markdown
> [!NOTE]
> First paragraph.
>
> Second paragraph.
```

### Not supported

Footnotes, `[[_TOC_]]` and other in-page tables of contents, front matter as metadata, site-generator syntax, transclusion, and `#123` or `@user` autolinks. See [Markup](references/markup.md#what-isnt-supported).

## Adding, renaming or deleting a page

**Add a page:**

1. Pick a unique sentence-case filename with hyphens, such as `Installation.md`.
1. Start the page with its intro paragraph, not a heading.
1. Add it to `_Sidebar.md` with link text that matches the title exactly: `[[Installation]]`, or `[[Getting started|Getting-started]]` for a multi-word title.
1. Link to it from any page that should mention it.

**Rename a page.** GitHub doesn't document redirects for renamed pages, and a request for a missing page was observed to redirect to Home, so every link to the old name must change:

1. Rename the file with `git -C <wiki> mv Old-name.md New-name.md`.
1. Find every link to the old name, in the wiki and in Source. Lookups ignore case and treat spaces and hyphens alike, so search loosely, with `[- ]` between words:

   ```bash
   grep -rniE --exclude-dir=.git '\[\[([^]|]*\|)?old[- ]name[]#]' <wiki>/
   grep -rni --exclude-dir=.git 'wiki/old-name' <wiki>/ <source>/
   ```

1. Update the `_Sidebar.md` entry: both the link text and the target.
1. Update the links in other wiki pages.
1. Links in Source that point to `.../wiki/Old-name` change through a pull request to Source, separately from the wiki commit. Tell the user which files need it.

**Delete a page:** run the same searches, remove or repoint every link, remove its `_Sidebar.md` entry, then `git -C <wiki> rm Page-name.md`.

**Change a heading:** its anchor changes too. Search `<wiki>/` and `<source>/` for `#old-slug` and update the links.

## Common pitfalls

- **Duplicate title.** A `# Title` line at the top shows the title twice.
- **Page-first links.** `[[Troubleshooting|Some heading]]` shows "Troubleshooting" and points to a missing page called "Some heading".
- **`.md` links.** `[text](Installation.md)` opens the raw file.
- **Relative Markdown links.** `[text](Installation)` works on normal pages, but is untested in the sidebar and footer. Use `[[...]]`, which renders as an absolute link everywhere.
- **Uppercase anchors.** GitHub doesn't normalise the fragment (observed), so `#Some-heading` may not reach the heading `some-heading`.
- **Hyphens in titles.** An ASCII hyphen becomes a space. Reword the title.
- **Extra sidebar or footer files.** GitHub was observed using any file whose name starts with `_Sidebar` or `_Footer`. Keep exactly one of each.
- **Subdirectories.** Pages in a subdirectory are served at `/wiki/<basename>`, and clashing basenames hide each other (observed).
- **Non-page Markdown.** A `CLAUDE.md`, `.claude/` folder or notes file is published as a public page.
- **Sidebar drift.** A page missing from `_Sidebar.md`, or with sidebar link text that doesn't match its title, is a bug.
- **Pushing too early.** A push to `master` publishes immediately, with no review step.

## Git workflow summary

1. Make sure the clone is on `master` and current: `git -C <wiki> switch master && git -C <wiki> pull --ff-only`.
1. Edit the pages, then check with `git -C <wiki> status` and `git -C <wiki> diff` that only the files you meant changed.
1. Stage the files by name and commit directly on `master`. Load the wow-commits skill for the message.
1. Ask the user before you push, and say which pages change. `git -C <wiki> push origin master` publishes straight away. Never push a wiki without the user's go-ahead.

## Reference files

- [Links and pages](references/links-and-pages.md): filenames and titles, the hyphen and space mapping, case-insensitive lookup, the flat namespace, `Home.md`, every link form, anchors and images. **Read before you add or rename a page, change a link or add an image.**
- [Markup](references/markup.md): what the wiki renders and what it doesn't, HTML sanitisation and a GitBook-to-wiki conversion table. **Read before you use anything beyond plain paragraphs, lists and links, or convert GitBook pages.**
- [Sidebar and footer](references/sidebar-and-footer.md): how `_Sidebar.md` and `_Footer.md` behave, a recommended structure and keeping the sidebar in sync. **Read before you edit either file.**
- [Git workflow](references/git-workflow.md): cloning, publishing on push, permissions, history and reverting, limits and search. **Read before you clone, commit, push or revert.**
