---
name: wow-docstrings
description: "House rules for docstrings and code comments. Applies only when ways of working is on. Use whenever a task writes or changes a function, method, class, type, module, package or script in any language; adds or edits a docstring, doc comment, JSDoc, Javadoc, XML doc comment, PowerShell comment-based help or code comment; or decides how much to document a parameter, return value or error."
---

# Docstrings

How to document code inside the code: with the language's own docstring form, kept short. **Load before you write or change a function, class or module.** These are house defaults: where a project's `CLAUDE.md` or linter sets its own docstring rules, follow the project.

## Use the language's own form

Give each module, class, function and method a docstring in the form its language and tools read, so editors, help commands and doc generators show it. Examples are a Python docstring, a Go doc comment, JSDoc or PowerShell comment-based help. Where a language has no such form, such as shell, use a comment straight above the definition.

```python
def load_config(path: Path) -> Config:
    """Read the config at path, filling in defaults for missing keys."""
```

## Keep it short

- Say what the unit does or is for, starting with a one-line summary. Often that line is all it needs.
- Describe a parameter, return value, error or side effect only when the signature and names don't make it obvious, such as a unit, an accepted range, when it raises or what it changes outside itself.
- Don't restate the signature or types, and don't add a section that lists every parameter just to fill it in.
- Where a project already uses a docstring style, such as Google or NumPy sections, follow it for the parts you include.
- Update a docstring in the same change as the code it describes.

## Comments inside the code

- Comment why, not what: a reason, a constraint or a workaround that the code can't show.
- Don't leave commented-out code, or comments that narrate the change, such as "now uses the new parser". The commit message says what changed.

## Checklist

Before you finish a change to code, check that:

- Each new or changed class, function and method has a short docstring in the language's own form, and so does each new module or script. A small fix doesn't call for docstrings on code it doesn't touch.
- Every docstring still matches the code, and says nothing the signature already makes obvious.
