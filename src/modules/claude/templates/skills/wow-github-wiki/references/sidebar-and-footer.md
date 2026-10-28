# Sidebar and footer

How `_Sidebar.md` and `_Footer.md` work on GitHub, the structure to use, and how to keep the sidebar in sync with the pages. Statements marked "observed" come from checking live GitHub wikis, not from GitHub's documentation.

## Contents

- [What GitHub documents](#what-github-documents): the two files and the web editor's links
- [What's observed](#whats-observed): layout, links, scope, the prefix-matching quirk and the rules that follow
- [Recommended structure](#recommended-structure): a suggested sidebar and footer
- [Keeping the sidebar in sync](#keeping-the-sidebar-in-sync): what to change and how to check it
- [Sources](#sources)

## What GitHub documents

- A file named `_Sidebar.<extension>` fills the wiki's sidebar, and `_Footer.<extension>` fills its footer.
- "Like every other wiki page, the extension you choose for these files determines how we render them." Use `_Sidebar.md` and `_Footer.md`, so both are GFM.
- In the web UI, editors can create them with "Add a custom sidebar" (on the right) and "Add a custom footer" (at the bottom of the wiki).
- That's all the docs say. They don't mention a header file, per-directory sidebars or footers, or the Pages list.

## What's observed

### Layout

- The built-in **Pages** box is always shown, at the top of the sidebar. It lists every page with a count and a filter box ("Find a page or section…"), and an expandable heading outline for each page.
- A custom `_Sidebar.md` renders in its own box **below** the Pages box, never in place of it. Below that comes "Clone this wiki locally".
- `_Footer.md` renders in the main column, after the page body.
- Without a `_Footer.md`, no footer is rendered.
- The "Add a custom sidebar" and "Add a custom footer" links seem to show only to people who can edit. Logged-out views of a wiki without a footer showed no such link, but the editor view wasn't checked.

Because the Pages box already lists every page and its headings, the custom sidebar's job is order and grouping, not completeness alone.

### Links in the sidebar and footer

- `[[...]]` links work in `_Sidebar.md`: `[[Page name]]` rendered as an `internal present` link to `/OWNER/REPO/wiki/Page-name`.
- The sidebar and footer render on every page, including `Home.md` at `/wiki` (no trailing slash). Nobody has tested whether GitHub compensates for that URL in relative sidebar and footer links, as it does in the Home page body. So use `[[...]]` for wiki pages and absolute URLs for everything else. See [Links and pages](links-and-pages.md#relative-markdown-links).

### Scope

- A root `_Footer.md` showed on a page stored in a subdirectory (`reference/test.md`, served at `/wiki/test`). That fits either a global footer or gollum-style inheritance, so it doesn't settle how per-directory files behave.
- Standalone gollum supports per-directory `_Sidebar`, `_Footer` and `_Header` files that apply to their directory and subdirectories. GitHub doesn't document this, and it wasn't tested.
- No `_Header` on GitHub: no live wiki page had a header region in its HTML, and GitHub's docs mention only sidebar and footer. Don't create `_Header.md`.

### The prefix-matching quirk

- A public wiki was observed with no `_Sidebar.md` or `_Footer.md` (its history shows both were deleted) but with one file whose name starts with `_Sidebar-` and one whose name starts with `_Footer-`, each followed by a contributor's name. GitHub renders those as its sidebar and footer, with "Edit sidebar" and "Edit footer" links. Neither appears in the Pages list.
- So GitHub appears to pick up any file whose name starts with `_Sidebar` or `_Footer`. That reading comes from this one wiki only; GitHub doesn't document the matching rule.

### Rules that follow

- Keep exactly one `_Sidebar.md` and one `_Footer.md`, both at the root of `<wiki>/`.
- Never give any other file a name that starts with `_Sidebar` or `_Footer`.
- Don't create `_Header.md`, and don't put pages, sidebars or footers in subdirectories. Images go in `images/`.

## Recommended structure

A wiki is for people who use the project. It has no contributor, development or design pages: load the wow-repo-docs skill for where those go. Don't add a Contributing section to the sidebar.

Before you change the sidebar, read `<wiki>/_Sidebar.md` and run `ls <wiki>` for the live state.

### Suggested structure

A suggestion for a wiki that's grown past a few pages. Add a sidebar entry in the same commit as its page, never ahead of it: a link to a missing page renders as `internal absent`.

```markdown
- [[Home]]

**Getting started**

- [[Installation]]
- [[Configuration]]

**Usage**

- [[Getting help|Getting-help]]

**Reference**

- [[Command reference|Command-reference]]
- [[Troubleshooting]]
```

- Use `-` bullets. If a page has child pages, nest them two spaces under their parent.
- Link text must equal the page's title (its filename with hyphens shown as spaces). `[[Home]]`, `[[Installation]]` and `[[Troubleshooting]]` can use the bare form because the title and filename are the same.
- No `#` heading: the sidebar box needs no title. When the list needs groups, use `**bold**` labels or `###` headings, not `#`. A group label is plain text, not a page.
- Keep `[[Home]]` first.

Keep `_Footer.md` short. It suits project-wide links that every page should carry, written as absolute URLs, for example:

```markdown
[Source code](https://github.com/OWNER/REPO) · [Report a problem](https://github.com/OWNER/REPO/issues)
```

Don't put anything in the footer that isn't true for every page, and no credentials, account URLs or internal hostnames.

## Keeping the sidebar in sync

Every time you add, rename or delete a page, update `_Sidebar.md` in the same commit.

- **Add**: insert `[[Title|File-name]]` in the right place.
- **Rename**: change both the link text and the target.
- **Delete**: remove the entry.
- **Retitle without renaming**: impossible. The title is the filename, so a new title means a rename.

To check that the sidebar and the pages agree, run:

```bash
# Pages on disk, without the sidebar and footer
ls <wiki>/*.md | xargs -n1 basename | sed 's/\.md$//' | grep -v '^_' | sort

# Targets linked from the sidebar
grep -oE '\[\[[^]]+\]\]' <wiki>/_Sidebar.md | sed -E 's/^\[\[([^]|]*\|)?//; s/\]\]$//; s/#.*//; s/ /-/g' | sort
```

The two lists should match, apart from case if a link uses a different case (lookups ignore case, but keep it identical). Then check each entry's link text against its filename with hyphens shown as spaces.

## Sources

- https://docs.github.com/en/communities/documenting-your-project-with-wikis/creating-a-footer-or-sidebar-for-your-wiki
- https://github.com/gollum/gollum/wiki/Formats-and-extensions
- https://github.com/gollum/gollum-lib/blob/v1.0.0/README.md
