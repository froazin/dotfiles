#!/usr/bin/env sh
#
# PostToolUse hook: lint a shell file Claude just edited and report problems
# back to Claude (exit 2 surfaces stderr to it). Silent when the file is not a
# shell file or the linter is not installed.
#
#   *.sh            shellcheck -s sh (SC1091 off: sources are dynamic), shfmt -i 4
#   zsh templates   zsh -n; shellcheck's bash mode cannot parse zsh syntax

file="$(python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2>/dev/null)"

[ -n "$file" ] && [ -f "$file" ] || exit 0

case "$file" in
*.sh)
    out=""

    if command -v shellcheck >/dev/null 2>&1; then
        out="$(shellcheck -s sh -e SC1091 -f gcc "$file" 2>&1)"
    fi

    if command -v shfmt >/dev/null 2>&1 && ! shfmt -i 4 -d "$file" >/dev/null 2>&1; then
        out="${out:+$out
}$file: not formatted, run: shfmt -i 4 -w $file"
    fi
    ;;
*.zsh | */.zshrc | */.zshenv | */.zprofile)
    command -v zsh >/dev/null 2>&1 || exit 0
    out="$(zsh -n "$file" 2>&1)"
    ;;
*)
    exit 0
    ;;
esac

[ -z "$out" ] && exit 0

printf '%s\n' "$out" >&2
exit 2
