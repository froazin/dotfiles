# Git workflow for the wiki

Where the wiki repository lives, how changes get published, and how to check and undo them. Statements marked "observed" come from checking live GitHub wikis and repositories, not from GitHub's documentation.

## Contents

- [The wiki is a separate repository](#the-wiki-is-a-separate-repository)
- [Cloning](#cloning)
- [Branch: master](#branch-master)
- [Publishing happens on push](#publishing-happens-on-push)
- [No pull requests](#no-pull-requests)
- [Every Markdown file is published](#every-markdown-file-is-published)
- [Who can edit](#who-can-edit)
- [Making a change](#making-a-change): the steps from edit to publish
- [Checking the state](#checking-the-state)
- [History and reverting](#history-and-reverting)
- [Limits](#limits) and [search](#search)
- [Sources](#sources)

## The wiki is a separate repository

- GitHub's docs: every wiki is its own Git repository, cloned from `https://github.com/OWNER/REPO.wiki.git`. It can be cloned only after a first page has been created on GitHub.
- The wiki is published at `https://github.com/OWNER/REPO/wiki`.
- Clone it as a standalone repository at `<wiki>/`, usually next to the Source clone at `<source>/`. The project's `CLAUDE.md` gives the paths if they differ.
- Every wiki edit, from the web editor or a push, is a commit in the wiki repository. Wiki commits never land in Source.
- Run Git commands with `-C`, for example `git -C <wiki> status`, so each one shows which repository it acts on.

## Cloning

If `<wiki>/` is missing, clone the wiki into the folder that should hold it:

```bash
git clone https://github.com/OWNER/REPO.wiki.git
```

This creates `<wiki>/` with `master` checked out. Before every change, make sure it's on `master` and up to date:

```bash
git -C <wiki> switch master
git -C <wiki> pull --ff-only
```

## Branch: master

- The wiki's default branch is `master`, not `main`. This is observed, not documented: `git ls-remote --symref` shows `HEAD` at `refs/heads/master` for every wiki checked, including wikis on repositories created in 2025 and 2026.
- GitHub's docs: "You and your collaborators can create branches when working on wikis, but only changes pushed to the default branch will be made live and available to your readers."
- So a branch in the wiki repository is only a draft. It isn't shown on the wiki, nothing reviews or merges it, and anyone who clones the wiki repository can still fetch it. Commit directly on `master` instead.

## Publishing happens on push

- A push to `master` is published straight away. There's no build, preview or approval step.
- Ask the user before every push to the wiki's `master`, and say which pages change. Never push a wiki without the user's go-ahead.

## No pull requests

- GitHub's wiki docs describe only two ways to change a wiki: the web editor and a direct push. Neither involves a pull request.
- That wikis can't take pull requests isn't stated by GitHub. It comes from community sources, which describe the wiki as allowing only direct commits.
- Projects that want review of wiki changes have to arrange it themselves. Some wikis' footers, for example, send contributors to a separate repository for pull requests (observed).
- Here, the review step is the user's go-ahead before a push.

## Every Markdown file is published

- GitHub publishes every `.md` file in the wiki repository as a page. Files in subdirectories are served at `/wiki/<basename>` (observed).
- So never commit `.claude/`, `CLAUDE.md`, notes or any other Markdown file that isn't meant to be a page. Keep Claude Code configuration out of the wiki repository.
- Stage files by name rather than with `git add -A`, so an untracked file in the clone isn't published by accident.

## Who can edit

From GitHub's docs:

- "By default, only people with write access to your repository can make changes to wikis."
- On a public repository, anyone who can change the repository's settings can let any GitHub user edit, by clearing **Settings > Features > Restrict editing to collaborators only**.
- A public repository's wiki is public. A private repository's wiki is visible only to people with access to the repository.
- Wikis are available on public repositories with GitHub Free, and on private repositories with GitHub Pro, Team and Enterprise.
- Turning the wiki off hides the content without erasing it. Turning it back on restores the pages.

People who can't edit the wiki should open an issue in Source that describes the change.

## Making a change

1. Bring `<wiki>/` up to date on `master` (see [Cloning](#cloning)).
1. Edit the pages, plus `_Sidebar.md` if pages were added, renamed or deleted.
1. Review the change:

   ```bash
   git -C <wiki> status
   git -C <wiki> diff
   ```

   Check that `status` lists only the files you meant to change.

1. Commit directly on `master`:

   ```bash
   git -C <wiki> add Home.md _Sidebar.md
   git -C <wiki> commit
   ```

   Name the files you changed. Renames and deletions made with `git mv` and `git rm` are already staged. Load the wow-commits skill for the commit message, and use a plain header such as `chore(docs): Add the install page`. Wiki commits don't affect Source's version.

1. Get the user's go-ahead, then publish:

   ```bash
   git -C <wiki> push origin master
   ```

1. Open the changed pages on `https://github.com/OWNER/REPO/wiki` and check that links show as present, alerts and tables render, and the sidebar is right.

Nothing else needs updating afterwards. If a page was renamed or deleted and Source links to it (for example from its `README.md`), those links change through a separate pull request to Source's default branch.

## Checking the state

```bash
git -C <wiki> status          # uncommitted wiki changes, and the current branch
git -C <wiki> log --oneline -5
git -C <wiki> fetch && git -C <wiki> status   # ahead of or behind origin/master?
```

- If `status` shows a branch other than `master`, switch to `master` before committing.
- Unpushed wiki commits aren't published. "Your branch is ahead of 'origin/master'" means there are commits waiting for the user's go-ahead.

## History and reverting

From GitHub's docs:

- "Because wikis are Git repositories, every change you make is a commit that you can view."
- Each page's history, opened from the revision link at the top of the page, lists who made each change, the commit message and when. Observed: it's also at `/wiki/Page-Name/_history`.
- Click a commit's SHA to see the page as it was, use **Compare Revisions** to diff two revisions, and **Revert Changes** to undo them. "You can only revert changes if you have permission to edit the wiki."

From Git, revert a bad commit with a new commit rather than rewriting `master`:

```bash
git -C <wiki> revert <sha>
```

Then push, with the user's go-ahead.

## Limits

GitHub's docs: "For performance reasons, wikis have a soft limit of 5,000 total files, regardless of file type. If you exceed this limit, some pages may be inaccessible to users. If you need a larger wiki, we recommend using GitHub Pages."

## Search

- GitHub's docs: "Search engines will only index wikis with 500 or more stars that you configure to prevent public editing." For content that must be indexed, GitHub suggests GitHub Pages.
- Wikis can be searched on GitHub itself, with the `user:`, `org:`, `repo:`, `in:title`, `in:body` and `updated:` qualifiers.

## Sources

- https://docs.github.com/en/communities/documenting-your-project-with-wikis/about-wikis
- https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages
- https://docs.github.com/en/communities/documenting-your-project-with-wikis/changing-access-permissions-for-wikis
- https://docs.github.com/en/communities/documenting-your-project-with-wikis/viewing-a-wikis-history-of-changes
- https://docs.github.com/en/communities/documenting-your-project-with-wikis/disabling-wikis
- https://docs.github.com/en/search-github/searching-on-github/searching-wikis
