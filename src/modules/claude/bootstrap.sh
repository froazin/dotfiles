#!/usr/bin/env sh

CLAUDE_SOFT_DEPS="jq python3"
CLAUDE_SUBDIRS="agents commands skills rules output-styles hooks"

# Deep merge of a template ($tpl) into the existing file ($cur), used for both
# settings.json and keybindings.json: template values win, objects merge key by
# key and lists are unioned, so keys Claude Code or the user write themselves
# (/model, /config, plugins, /permissions, own bindings) survive. Each file is
# slurped on its own so one can never shift the other.
# shellcheck disable=SC2016 # $a, $b, $k, $o, $i, $id, $cur and $tpl are jq variables.
CLAUDE_JSON_MERGE='
def merge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
  elif ($a | type) == "array" and ($b | type) == "array" then
    $a + ($b - $a)
  else
    $b
  end;
# Lists of objects identified by a key ($id): each template object is merged
# into the first existing one with the same key, or appended if none has it.
def merge_by($a; $b; $id):
  reduce $b[] as $o ($a;
    (map(.[$id]?) | index([$o[$id]])) as $i
    | if $i == null then . + [$o] else .[$i] = merge(.[$i]; $o) end);
# Whitespace only: passes [ -s ] but holds no values.
if ($cur | length) == 0 then
  $tpl[0]
elif ($cur | length) != 1 or ($cur[0] | type) != "object" then
  error("not a single JSON object")
else
  merge($cur[0]; $tpl[0])
  # A union would keep an outdated copy of a template hook next to the new
  # one, so existing hooks with a template command are replaced instead.
  | reduce ($tpl[0].hooks // {} | keys_unsorted[]) as $e (.;
      ([$tpl[0].hooks[$e][]?.hooks[]?.command]) as $cmds
      | .hooks[$e] = ([$cur[0].hooks[$e][]?
          | .hooks |= map(select(.command as $c | $cmds | index([$c]) | not))
          | select(.hooks | length > 0)] + $tpl[0].hooks[$e]))
  # A union would likewise add a second block for a context whenever the
  # template block changes, so keybindings merge block by context.
  | if $tpl[0] | has("bindings") then
      .bindings = merge_by($cur[0].bindings // []; $tpl[0].bindings; "context")
    else
      .
    end
end
'

claude_check_soft_deps()
{
    failed="false"

    for cmd in $CLAUDE_SOFT_DEPS; do
        if command -v "$cmd" > /dev/null 2>&1; then
            log debug "Found soft dependency: $cmd"
        else
            case "$cmd" in
                jq) log error "Missing dependency: jq is not installed. Settings will only be seeded where none exist, not merged into existing ones." ;;
                python3) log error "Missing dependency: python3 is not installed. The commit-signing guard and no-session-links hooks are installed but do nothing until it is." ;;
                *) log error "Missing dependency: $cmd is not installed." ;;
            esac
            failed="true"
        fi
    done

    if [ "$failed" = "true" ]; then
        return 1
    fi

    return 0
}

claude_create_dirs()
{
    claude_dir="$1"
    failed="false"

    ensure_dir "$claude_dir" || return 1

    # Credentials and session history live here in plain text.
    chmod 700 "$claude_dir" > /dev/null 2>&1 || {
        log error "Failed to restrict permissions on <$claude_dir>."
        failed="true"
    }

    for subdir in $CLAUDE_SUBDIRS; do
        ensure_dir "$claude_dir/$subdir" || failed="true"
    done

    if [ "$failed" = "true" ]; then
        return 1
    fi

    return 0
}

claude_merge_json()
{
    src="$1"
    dest="$2"

    if [ ! -f "$src" ]; then
        log error "Template not found: <$src>."
        return 1
    fi

    if [ -L "$dest" ]; then
        log warning "Existing file <$dest> is a symbolic link and will be left alone."
        return 1
    fi

    if [ ! -s "$dest" ]; then
        install_file "$src" "$dest" || return 1
        log info "Claude Code configuration created at <$dest>."
        return 0
    fi

    if [ ! -w "$dest" ]; then
        log warning "Existing file <$dest> is read-only and will be left alone."
        return 1
    fi

    if ! command -v jq > /dev/null 2>&1; then
        log error "Cannot merge into existing <$dest> without jq; it was left unchanged."
        return 1
    fi

    # Start from a copy so the replacement keeps the original's mode.
    tmp="$dest.dotfiles.$$"
    cp -p "$dest" "$tmp" > /dev/null 2>&1 || {
        rm -f "$tmp"
        log error "Failed to write a temporary file next to <$dest>."
        return 1
    }

    jq_error="$(jq -n --slurpfile cur "$dest" --slurpfile tpl "$src" "$CLAUDE_JSON_MERGE" 2>&1 > "$tmp")" || {
        rm -f "$tmp"
        # The log's JSON line cannot hold " or \ (octal 042, 134).
        jq_error="$(printf '%s\n' "$jq_error" | head -n 1 | tr -d '\042\134')"
        log error "Failed to merge <$src> into <$dest>, which was left unchanged: $jq_error"
        return 1
    }

    if cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        log debug "<$dest> is already up to date."
        return 0
    fi

    mv -f "$tmp" "$dest" > /dev/null 2>&1 || {
        rm -f "$tmp"
        log error "Failed to write <$dest>."
        return 1
    }

    log info "Merged dotfiles configuration into <$dest>."
    return 0
}

claude_install_templates()
{
    templates="$1"
    claude_dir="$2"
    failed="false"

    # settings.json and keybindings.json are merged, not copied. Template paths
    # never contain newlines, so the list is split on them.
    files="$(CDPATH='' cd -- "$templates" && find . -type f ! -path ./settings.json ! -path ./keybindings.json ! -path '*/__pycache__/*' ! -name '*.pyc')" || {
        log error "Failed to list templates in <$templates>."
        return 1
    }

    old_ifs="$IFS"
    IFS='
'
    for file in $files; do
        file="${file#./}"
        install_file "$templates/$file" "$claude_dir/$file" || {
            failed="true"
            continue
        }

        if [ -x "$templates/$file" ]; then
            chmod 755 "$claude_dir/$file" > /dev/null 2>&1 || {
                log error "Failed to make <$claude_dir/$file> executable."
                failed="true"
            }
        fi
    done
    IFS="$old_ifs"

    if [ "$failed" = "true" ]; then
        return 1
    fi

    return 0
}

claude_install_config()
{
    log info "Installing Claude Code configuration."

    templates="$(dirname "$0")/modules/claude/templates"
    claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    config_failed="false"

    claude_create_dirs "$claude_dir" || config_failed="true"
    claude_install_templates "$templates" "$claude_dir" || config_failed="true"
    claude_merge_json "$templates/settings.json" "$claude_dir/settings.json" || config_failed="true"
    claude_merge_json "$templates/keybindings.json" "$claude_dir/keybindings.json" || config_failed="true"

    if [ "$config_failed" = "true" ]; then
        return 1
    fi

    log info "Claude Code configuration installed to <$claude_dir>."
    return 0
}

bootstrap()
{
    errors=""

    log info "Bootstrapping Claude Code configuration."

    claude_check_soft_deps || errors="true"

    claude_install_config || {
        log error "Failed to install Claude Code configuration."
        errors="true"
    }

    if [ -n "$errors" ]; then
        log warning "Claude Code configuration completed with errors."
        return 1
    fi

    log info "Claude Code configuration bootstrapped successfully."
    return 0
}
