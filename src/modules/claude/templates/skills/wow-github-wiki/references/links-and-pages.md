# Links and pages

How GitHub turns wiki files into pages, and how to link to them. Statements marked "observed" come from checking live GitHub wikis, not from GitHub's documentation. File and page names in the examples, such as `Installation` and `Configuration`, are illustrations: check `ls <wiki>` for the pages a wiki actually has.

## Contents

- [Filenames and titles](#filenames-and-titles): the filename is the title, hyphens and spaces, real hyphens, forbidden characters, naming, case-insensitive lookup, the flat namespace, `Home.md`
- [Link forms](#link-forms): which form to use, `[[...]]` tag links, relative links, links to and from Source
- [Heading anchors](#heading-anchors): slug rules and observed details
- [Images](#images): where to store them and how to embed them
- [Sources](#sources)

## Filenames and titles

### The filename is the title

- GitHub's docs: "The filename determines the title of your wiki page, and the file extension determines how your wiki content is rendered."
- `.md` and `.markdown` use the Markdown renderer. Other extensions pick other renderers (`.textile`, `.rdoc`, `.org`, `.creole`, `.mediawiki`, `.rst`, `.asciidoc` and more). Use `.md` only.
- GitHub renders the title as its own H1 in the page header, above the content (observed). A `# Heading` in the file doesn't replace it. It renders as a second H1 in the body, so a file that starts with `# Page title` shows the title twice.
- GitHub's docs say nothing about H1s. Leaving out the H1 and starting sections at `##` is the house convention, based on the observed behaviour.
- Standalone gollum (the engine GitHub's wiki grew from) can override the title with the first H1 or a front matter `title:`. GitHub hasn't been seen applying the H1 override, and whether it honours a front matter title is unverified. Don't rely on either.

### Hyphens and spaces

Observed on GitHub:

- The title is the filename without its extension, with each ASCII hyphen shown as a space. `Release-Notes-Archive.md` is displayed as "Release Notes Archive".
- The title keeps the filename's case, whatever the case of the URL.
- Filenames with literal spaces also work. `Release notes.md` is served at `/wiki/Release-notes`. In the URL a space or a hyphen becomes `-`, and in the title each becomes a space.
- So `Getting started.md` and `Getting-started.md` would map to the same page. Use hyphens, never spaces, so the names stay unambiguous.
- Each character maps on its own: `Version 2 - Migration.md` is displayed with three spaces in place of ` - ` and served at `/wiki/Version-2---Migration`.

### Real hyphens

- Because an ASCII hyphen becomes a space, a title that needs a visible hyphen can't use one.
- Observed: wikis whose titles contain a real hyphen store it in the filename as U+2010 HYPHEN (`‐`). For example, `Roadmap‐2021‐2022.md` is served at `/wiki/Roadmap%E2%80%902021%E2%80%902022`.
- The ASCII-hyphen URL `/wiki/Roadmap-2021-2022` doesn't resolve (it redirected to the wiki's Home). Links to such pages must use the U+2010 character.
- That GitHub's web editor creates these filenames is inferred, not checked.
- Don't put hyphens in titles. Reword instead.

### Forbidden characters

GitHub's docs: "Don't use the following characters in your wiki page's titles: `\ / : * ? " < > |`. Users on certain operating systems won't be able to work with filenames containing these characters."

### Naming convention

- Sentence case, words joined with ASCII hyphens, `.md` extension: `Getting-started.md`, displayed as "Getting started".
- Never name a file starting with `_Sidebar` or `_Footer` unless it's the one root `_Sidebar.md` or `_Footer.md` (see [Sidebar and footer](sidebar-and-footer.md)).

### Case-insensitive lookup

Observed, not documented:

- Page URLs ignore case. `/wiki/performance-issues` returns the page titled "Performance Issues", and `/wiki/home` redirects to `/wiki`.
- `[[...]]` links also match case-insensitively and treat spaces as hyphens. `[[Setup|Project-setup]]` resolves to the file `Project-Setup.md`, and GitHub rewrites the link's `href` to the file's real case.
- Gollum 5 made filenames case-sensitive. GitHub still behaves like older gollum here.
- Treat two names that differ only in case as the same page. Don't create both.

### Flat namespace and basename collisions

Observed, not documented:

- A page in a subdirectory of the wiki repository is served at `/wiki/<basename>`, with its basename as the title. `reference/test.md` is served at `/wiki/test`, titled "test". `/wiki/reference/test` doesn't resolve.
- The directory isn't part of the URL, the title or the Pages list. GitHub has no folder grouping.
- Collisions: in a wiki with both `README.md` and `debugging/README.md`, the Pages box lists "README" twice, both links go to `/wiki/README`, and that URL renders the root file. The copy in the subdirectory can't be reached.
- So every basename must be unique: keep every page at the root of `<wiki>/`.

### Home.md

- `Home.md` is the landing page, served at `/OWNER/REPO/wiki`, so the full URL is `https://github.com/OWNER/REPO/wiki`. The URL has no trailing slash, which matters for [relative links](#relative-markdown-links).
- Observed: `/wiki/Home` redirects (301) to `/wiki`. Gollum documents `Home.ext` as the wiki's entrance page; GitHub's docs don't name it.

### Page URLs with `.md`

Observed: `/wiki/Page-Name.md` redirects (302) to the raw file on `raw.githubusercontent.com/wiki/OWNER/REPO/Page-Name.md`, not the rendered page. Never put `.md` in a link to a page.

## Link forms

### Which form to use

| Target | Use | Example |
| --- | --- | --- |
| Another wiki page | `[[Link text\|Page-Name]]` | `[[Getting started\|Getting-started]]` |
| Another page, title as link text | `[[Page name]]` | `[[Home]]`, `[[Troubleshooting]]` |
| A heading on another page | `[[Link text\|Page-Name#slug]]` | `[[Signing in\|Configuration#signing-in]]` |
| A heading on the same page | `[text](#slug)` | `[the checklist](#checklist)` |
| A file in Source | absolute URL to the `main` branch | `[MIT License](https://github.com/OWNER/REPO/blob/main/LICENSE)` |
| A wiki page, from Source | absolute wiki URL | `[Signing in](https://github.com/OWNER/REPO/wiki/Configuration#signing-in)` |
| An external site | `[text](https://...)` | `[Docker documentation](https://docs.docker.com/)` |

Don't use:

- `[text](Page-Name.md)`: opens the raw Markdown file.
- `[[Page-Name|Link text]]` (page first): breaks in `.md` pages.
- `[text](Page-Name)` (relative, extensionless): renders on normal pages and on `Home.md`, but it's untested in `_Sidebar.md` and `_Footer.md`. Use `[[...]]` so every link works the same way.

### Wiki tag links: `[[...]]`

Gollum tag links are the main way to link between pages.

```markdown
See [[Installation]] before you configure the helper.
See [[Signing in|Configuration#signing-in]].
Back to [[Home]].
```

- Order: link text first, page second. Observed: `[[known problems|Known Problems]]` renders as a link with the text "known problems" to `/wiki/Known-Problems`. Gollum's docs agree: "the first thing in the link is what is displayed".
- A bare `[[Release notes]]` links to `/wiki/Release-notes` and shows "Release notes". In the bare form, write the title with spaces so the link text matches the title.
- GitHub renders `[[...]]` as an absolute link, `/OWNER/REPO/wiki/Page-Name`, with class `internal present`. A target that doesn't exist gets class `internal absent`. That makes `[[...]]` safe on every page, including `Home.md`, `_Sidebar.md` and `_Footer.md`.
- `#slug` after the page name links to a heading. GitHub passes the fragment through unchanged, case included (see [Heading anchors](#heading-anchors)).
- External URLs also work in tag form, such as `[[here|https://example.com/]]` (observed). Prefer normal Markdown for external links.
- To write about the syntax itself, put it in a code span or a code block. GitHub keeps tags inside `<code>` literal (observed). Gollum's apostrophe escape (`'[[Page]]`) wasn't tested on GitHub.

Why not page first:

- GitHub's editing-wiki-content doc currently shows `[[Nameofwikipage|Link Text]]`, labelled "With MediaWiki syntax". Gollum reverses the parts only for `.mediawiki`/`.wiki` and `.creole` files, so that form may be right for MediaWiki pages, but that wasn't tested.
- In a `.md` page the first part is always the link text. Observed: `[[the steps|Release process]]` renders as an `internal absent` link to `/wiki/Release-process`.
- The doc has flipped between the two orders more than once. Ignore it for `.md` pages.

### Relative Markdown links

- `[text](Page-Name)` and `[text](Page-Name#slug)` are passed through unchanged as relative `href`s (observed), and the browser resolves them against the page's URL.
- On a page at `/OWNER/REPO/wiki/Some-page`, that gives `/OWNER/REPO/wiki/Page-Name`, which works.
- `Home.md` is served at `/OWNER/REPO/wiki` with no trailing slash, so plain URL resolution would give `/OWNER/REPO/Page-Name`, outside the wiki. GitHub compensates in the Home page body. Observed: on a Home page, the source `[...](Screenshots)` renders as `href="wiki/Screenshots"`.
- Whether GitHub makes the same rewrite in `_Sidebar.md` and `_Footer.md` wasn't tested. They render on every page, including Home.
- So don't use relative Markdown links between pages. `[[...]]` renders the same absolute link everywhere, and GitHub marks a missing target as absent.

### Links to and from Source

- Link to files in Source with absolute URLs to the `main` branch. Relative paths would resolve inside the wiki.
- Files in Source (`<source>/`), such as `README.md`, can't use `[[...]]`. Link to the wiki with the absolute page URL, such as `https://github.com/OWNER/REPO/wiki` or `https://github.com/OWNER/REPO/wiki/Configuration#signing-in`.
- Keep links from Source up to date when you rename a page or a heading. Source is a separate repository with its own pull requests, so a fix there is a separate change from the wiki commit.
- `[[...]]` links don't render in an ordinary Markdown viewer, such as an IDE preview or Source's file view on GitHub. Extensionless relative links don't resolve there either (inferred, not documented). Check rendering on the wiki itself.

## Heading anchors

GitHub's slug rules for rendered Markdown, which apply to wiki headings:

- Letters are lowercased.
- Spaces become hyphens.
- Punctuation is removed.
- A heading that repeats an earlier one gets `-1`, then `-2`, and so on.

| Heading | Anchor |
| --- | --- |
| `## Signing in to GitHub` | `#signing-in-to-github` |
| `### Viewing and Editing Pages, GlobalTOC Macro` | `#viewing-and-editing-pages-globaltoc-macro` |
| A second `## Screenshot` | `#screenshot-1` |

Observed details:

- The rendered id is `user-content-<slug>`, on an anchor next to the heading. Links use the bare `#slug`, without `user-content-`.
- Fragments aren't normalised. `[[customise|Configuration#Customisation]]` keeps `#Customisation`, which doesn't match the id `customisation`. Always write anchors in lowercase.
- A hand-written `<a id="name"></a>` is kept, with its id prefixed to `user-content-name`, and `#name` links to it.

When you reword a heading, its anchor changes. Search `<wiki>/` and `<source>/` for the old `#slug` and update the links. Keep existing headings' wording unless there's a reason to change it.

## Images

- GitHub's docs: "Wikis can display PNG, JPEG, and GIF images."
- Store images in the wiki repository under `images/` (`<wiki>/images/`) and embed them with a Markdown image whose path starts at the wiki root, without a leading slash:

  ```markdown
  ![Alt text that describes the image](images/example.png)
  ```

- Observed: GitHub passes the `src` through unchanged. On a page at `/OWNER/REPO/wiki/Page`, `images/example.png` loads `/OWNER/REPO/wiki/images/example.png`, which redirects to `https://raw.githubusercontent.com/wiki/OWNER/REPO/images/example.png`.
- Paths relative to a file's own directory, such as `../images/example.png`, break, because every page URL is flat under `/wiki/`.
- On `Home.md`, GitHub rewrites relative link targets to compensate for the `/wiki` URL with no trailing slash, but that wasn't tested for image paths, or for `_Sidebar.md` and `_Footer.md`. In those three files, use the absolute raw URL, `https://raw.githubusercontent.com/wiki/OWNER/REPO/images/example.png`, and check the published page.
- Always write meaningful alt text.
- GitHub's docs also show the gollum tag form for an image in the main repository, by its browser URL: `[[https://github.com/OWNER/REPO/blob/main/img/octocat.png|alt=octocat]]`. The tag form for files stored in the wiki repository wasn't verified on GitHub, so use the Markdown form.
- Raw `<img>` HTML with `width` and `alt` survives sanitisation (observed), if you need to size an image.

## Sources

- https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages
- https://docs.github.com/en/communities/documenting-your-project-with-wikis/editing-wiki-content
- https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax
- https://github.com/github/docs/issues/24850
- https://github.com/gollum/gollum-lib/blob/v1.0.0/README.md
- https://github.com/gollum/gollum-lib/blob/master/lib/gollum-lib/filter/tags.rb
- https://github.com/gollum/gollum/wiki/Formats-and-extensions
- https://github.com/gollum/gollum/wiki/6.0-Release-Notes
