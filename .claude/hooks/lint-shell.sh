#!/usr/bin/env sh
#
# PostToolUse hook; exit 2 surfaces stderr to Claude. Options live in
# .shellcheckrc and .editorconfig; any shfmt formatting flag makes it ignore
# the latter. Neither tool parses zsh, so zsh files only get zsh -n.

file="$(python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2> /dev/null)"

[ -n "$file" ] && [ -f "$file" ] || exit 0

case "$file" in
    *.sh)
        out=""

        if command -v shellcheck > /dev/null 2>&1; then
            out="$(shellcheck -f gcc "$file" 2>&1)"
        fi

        if command -v shfmt > /dev/null 2>&1 && ! shfmt -d "$file" > /dev/null 2>&1; then
            out="${out:+$out
}$file: not formatted, run: shfmt -w $file"
        fi
        ;;
    *.zsh | */.zshrc | */.zshenv | */.zprofile)
        command -v zsh > /dev/null 2>&1 || exit 0
        out="$(zsh -n "$file" 2>&1)"
        ;;
    *)
        exit 0
        ;;
esac

[ -z "$out" ] && exit 0

printf '%s\n' "$out" >&2
exit 2
