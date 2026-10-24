---
paths:
  - "**/*.py"
  - "pyproject.toml"
  - "pyrightconfig.json"
  - ".python-version"
---

# Python

- Python the dotfiles install (the claude module's hooks) runs on the system
  `python3` and uses the standard library only. Never add a runtime
  dependency, and never one from PyPI: dev tools in the `dev` dependency
  group are the only packages uv manages.
- uv uses the system interpreter (`[tool.uv]` in `pyproject.toml`), so
  `requires-python`, `.python-version` and pyright's `pythonVersion` track
  what Ubuntu ships.
- Everything passes `uv run pyright` in strict mode: annotate every function,
  and narrow JSON input with `as_object`/`as_str` rather than `Any`.
- Format and lint with `uv run ruff format` and `uv run ruff check`; their
  settings are in `pyproject.toml`, pyright's in `pyrightconfig.json`.
- Tests are pytest, next to the module (`src/modules/<name>/tests/`).
  Commit-signing guard cases go in `commit_signing_guard.cases`, and
  no-session-links cases in `test_no_session_links.py`; add one for every
  fix. Build fixture session links from parts, or the installed hook blocks
  writing the test file.
- Hooks are run by a `.sh` wrapper with `python3 -I`, so a module beside the
  script or on `PYTHONPATH` can't shadow the standard library.
