---
name: wow-markdown
description: "House rules for GitHub Flavored Markdown. Applies only when ways of working is on. Use whenever a task writes or edits a Markdown (.md) file or Markdown in an issue, pull request or comment, and especially when it adds a list, code block, table, link or heading anchor, an alert ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]), a collapsed <details> section, a task list, a footnote, math, a <kbd> key, an HTML comment, an image, an issue reference or an @mention; converts docs from another Markdown flavour such as GitBook, MkDocs, Docusaurus or Hugo; adds YAML front matter; or checks whether a feature works in a repository file, an issue or a GitHub wiki."
---

# Markdown

How to write Markdown in a project: GitHub Flavored Markdown (GFM), the GitHub features to use and where they don't work. It's for anyone writing a doc, README, `CLAUDE.md`, rule, skill, wiki page, issue or pull request (PR). **Load before you write or edit Markdown.** These are house defaults: where a project's `CLAUDE.md` sets other Markdown rules, follow the project.

## Write GitHub Flavored Markdown

- Write [GFM](https://github.github.com/gfm/) as GitHub renders it, with GitHub's extensions below. Name every Markdown file `.md`.
- Don't use another flavour or a site generator's syntax: no GitBook `{% ... %}` blocks, MkDocs `!!!` admonitions, Docusaurus `:::note` blocks or Hugo shortcodes.
- Don't add YAML front matter, except where a tool needs it, such as the `name` and `description` of a Claude Code skill's `SKILL.md`.
- A GitHub wiki renders less than a repository does. See [Where features don't work](#where-features-dont-work).

## Basics

- Use `-` for bullets. Use `1.` for every item in an ordered list, so items can move without renumbering.
- Give every fenced code block a language, such as `bash`, `json` or `markdown`. Use `text` for output, commit messages and other plain text.
- Inside a list item, put a blank line before a code block and indent it three spaces, so it stays in the item.
- Use a GFM table when each item has two or more attributes. Escape a `|` inside a cell as `\|`.
- Put file names, paths, commands, branch names, environment variables and literal values in code spans.
- Use bold for the label at the start of a bullet, such as **Wiki:**, and for a word the reader mustn't miss, such as **both**. Don't bold whole sentences.
- Write link text that says where the link goes, on one line. Never use "click here" or a bare "this".
- Link to other files in the same repository with relative paths, and to a heading with its anchor: `[Checklist](#checklist)`. Anchors are lowercase, with spaces as hyphens and punctuation removed.
- Don't end a line with two spaces to break it: they're invisible, and editors strip them. Start a new paragraph or list item instead.

## GitHub features to use

| Feature | Write | Use it for |
| --- | --- | --- |
| Alert | `> [!NOTE]` and four other types | Something the reader would regret missing. See [Alerts](#alerts) |
| Collapsed section | `<details>` and `<summary>` | Optional detail most readers skip. See [Collapsed sections](#collapsed-sections) |
| Diagram | A `mermaid` code block | Anything easier to see than to read, in any type Mermaid documents, such as an architecture, flow, sequence, state machine or data model. Load the wow-diagrams skill |
| Task list | `- [ ]` and `- [x]` | The state of work in an issue or PR description |
| Footnote | `[^1]` in the text and `[^1]: Note.` at the end | A source or an aside that would break the sentence |
| Math | `$...$` inline, `$$...$$` or a `math` code block | A formula |
| Keyboard key | `<kbd>Ctrl</kbd>+<kbd>C</kbd>` | A key or shortcut the reader presses |
| Comment | `<!-- ... -->` | A note to editors. Anyone can read it in the source, so keep private values out |
| Issue or PR reference | `#123`, `OWNER/REPO#123` | An issue, PR or commit, in an issue, PR, comment or commit message |

- GitHub links `#123`, `OWNER/REPO#123` and commit SHAs only in conversations, such as issues, PRs and comments. In a file or wiki page, write a full link instead.
- An `@name` mention notifies that person or team. Write one only when you mean to notify them. In docs, refer to people by role.
- Don't use strikethrough (`~~text~~`) in docs. Describe what's true now.
- Other HTML is sanitised: GitHub strips `style` and `class` attributes and scripts. Use HTML only for the elements in the table, and for `<img>` with `width` and `alt`.

### Alerts

Use the five types for what they mean: `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` and `[!CAUTION]`. Use them sparingly.

```markdown
> [!WARNING]
> First paragraph.
>
> Second paragraph.
```

- Put the type marker alone on the first line, and start every line with `>`, including the blank line between paragraphs.
- Don't put an alert inside a list, a table, a collapsed section or another blockquote. GitHub's docs say alerts can't be nested in other elements.

### Collapsed sections

````markdown
<details>
<summary>Full output of the failing test</summary>

The body, in Markdown.

```text
...
```

</details>
````

- Write the summary as a label that says what's inside.
- Leave a blank line after `</summary>` and before `</details>`, so the body renders as Markdown.
- Add `open` (`<details open>`) only when most readers need the content, but it would still make the page long.
- Never hide a step the reader has to follow, or a warning.

## Where features don't work

| Feature | Repository files | Issues, PRs and comments | GitHub wiki |
| --- | --- | --- | --- |
| Footnotes | Yes | Yes | No. GitHub's docs: "Footnotes are not supported in wikis" |
| `#123` and `@name` links | No (inferred) | Yes | No |
| Task lists | Shown, but readers can't tick them (inferred) | Yes, interactive | Shown, but readers can't tick them (observed) |
| Alerts | Yes | Yes | Yes (observed) |
| `<details>` | Yes | Yes | Yes (observed) |
| Mermaid and math | Yes | Yes | Yes |
| `[[Page-Name]]` links | No | No | Yes |

For everything else a wiki renders or strips, load the wow-github-wiki skill and read its markup reference.

## Checklist

Before you finish, check that:

- It's plain GFM, with no other flavour's syntax and no front matter that a tool doesn't need.
- Every code block has a language, and every ordered item is `1.`.
- Every alert and collapsed section follows the rules above, and nothing essential is collapsed.
- Every diagram follows the wow-diagrams skill.
- Nothing that doesn't work in the destination is used, such as a footnote on a wiki page.

## Sources

- https://github.github.com/gfm/
- https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax
- https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-collapsed-sections
- https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions
- https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls
