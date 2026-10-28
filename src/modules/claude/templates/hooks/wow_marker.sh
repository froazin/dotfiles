#!/usr/bin/env sh
#
# Claude Code ways-of-working hook. A .wow file turns the ways of working on
# for the directory that holds it and everything below, up to and including
# the workspace root ${WORKSPACE_DIR:-${SUDO_HOME:-$HOME}/workspaces}. Each
# settings.json registration passes a mode, and the command strings stay
# stable because the settings merge replaces hooks by command. It runs on its
# own under Claude Code, so it uses shell builtins plus sed, mkdir, rmdir, rm
# and sleep only. Any error means "off" and silence: the only thing it ever
# blocks is a wow-* skill, and only when nothing touched is marked.
#
# Modes: session-start, subagent-start, pre-tool, post-bash, pre-skill,
# expand, session-end, and status [dir] for people and tests.

unset CDPATH

WOW_DENY="Ways of working is off: no directory touched in this session has a .wow marker, so wow-* skills don't apply."

# Prints <workspaces>/<rel>, or returns 1 when rel holds a character that
# would need escaping in JSON (or that could leak more than a path should).
wow_show()
{
    case $1 in
        *[!A-Za-z0-9._/@+-]*) return 1 ;;
        '') wow_shown="<workspaces>" ;;
        *) wow_shown="<workspaces>/$1" ;;
    esac
}

# Sets wow_key (on:<rel marker dir> or off) and wow_line for directory $1,
# relative to the session directory when it isn't absolute. Returns 0 when on.
wow_find()
{
    wow_key="off"
    wow_line="Ways of working: off (outside <workspaces>)."
    [ -n "$wow_root_ok" ] || return 1

    wow_d=$1
    case $wow_d in
        /*) ;;
        *)
            # The session directory may be gone, such as a removed worktree.
            [ -n "$wow_start" ] || return 1
            wow_d="$wow_start/$wow_d"
            ;;
    esac
    # A missing directory (such as a Write that creates one) counts as its
    # nearest existing ancestor. cd -P leaves the physical path in PWD.
    until cd -P -- "${wow_d:-/}" 2> /dev/null; do
        [ -n "$wow_d" ] || return 1
        wow_d=${wow_d%/*}
    done
    wow_d=${PWD%/}

    case $wow_d in
        "$wow_root" | "$wow_root"/*) ;;
        *) return 1 ;;
    esac

    wow_m=$wow_d
    until [ -f "$wow_m/.wow" ]; do
        if [ "$wow_m" = "$wow_root" ]; then
            wow_rel=${wow_d#"$wow_root"}
            if wow_show "${wow_rel#/}"; then
                wow_line="Ways of working: off for $wow_shown (no .wow marker at or above it)."
            else
                wow_line="Ways of working: off (no .wow marker at or above this directory)."
            fi
            return 1
        fi
        wow_m=${wow_m%/*}
    done

    wow_rel=${wow_m#"$wow_root"}
    wow_rel=${wow_rel#/}
    wow_key="on:$wow_rel"
    if wow_show "$wow_rel"; then
        if [ -n "$wow_rel" ]; then
            wow_line="Ways of working: on for $wow_shown (marker $wow_shown/.wow)."
        else
            wow_line="Ways of working: on for $wow_shown (marker <workspaces>/.wow)."
        fi
    else
        # The state file holds one line, and such a path may hold a newline.
        wow_key="on:?"
        wow_line="Ways of working: on (marker found)."
    fi
    return 0
}

# Reads the hook JSON on stdin with one sed process. Each wanted key whose
# value is a string without escapes becomes a key=value line; anything else
# counts as absent. Newlines are folded first, so only those lines can start
# with key=. LC_ALL=C matches bytes, so an invalid UTF-8 byte in an earlier
# value can't stop a later key matching.
wow_read_input()
{
    wow_fields=$(LC_ALL=C sed -n -e 'H;$!d;x;s/\n/ /g' \
        -e 's/"\(session_id\|agent_id\|file_path\|notebook_path\|path\|skill\|command_name\|source\)"[[:space:]]*:[[:space:]]*"\([^"\\]*\)"/\n\1=\2\n/g' \
        -e 't l' -e ':l' -e '/^[a-z_]\{1,\}=/P' -e 's/^[^\n]*\n//' -e 't l' 2> /dev/null)

    wow_sid="" wow_aid="" wow_file="" wow_path="" wow_skill="" wow_cname=""
    wow_ifs=$IFS
    IFS='
'
    set -f
    for wow_kv in $wow_fields; do
        wow_v=${wow_kv#*=}
        case $wow_kv in
            session_id=*) [ -n "$wow_sid" ] || wow_sid=$wow_v ;;
            agent_id=*) [ -n "$wow_aid" ] || wow_aid=$wow_v ;;
            file_path=* | notebook_path=*) [ -n "$wow_file" ] || wow_file=$wow_v ;;
            path=*) [ -n "$wow_path" ] || wow_path=$wow_v ;;
            skill=*) [ -n "$wow_skill" ] || wow_skill=$wow_v ;;
            command_name=*) [ -n "$wow_cname" ] || wow_cname=$wow_v ;;
        esac
    done
    set +f
    IFS=$wow_ifs
}

# Sets wow_dir to the state directory and wow_base to this session's file
# prefix. Returns 1 (stateless) for an unsafe id or an unusable directory.
wow_state()
{
    case $wow_sid in
        '' | *[!A-Za-z0-9_-]*) return 1 ;;
    esac
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
        wow_dir="$XDG_RUNTIME_DIR/claude-wow"
    else
        wow_dir="${XDG_CACHE_HOME:-${HOME:-}/.cache}/claude-wow"
    fi
    case $wow_dir in
        /*) ;;
        *) return 1 ;;
    esac
    if [ ! -d "$wow_dir" ]; then
        [ -d "${wow_dir%/*}" ] || mkdir -p -- "${wow_dir%/*}" 2> /dev/null
        # Another hook may create it first.
        mkdir -m 700 -- "$wow_dir" 2> /dev/null || [ -d "$wow_dir" ] || return 1
    fi
    [ -w "$wow_dir" ] || return 1
    wow_base="$wow_dir/$wow_sid"
}

# The state file for this session, or for this subagent inside it. Returns 1
# when the agent id is unsafe.
wow_state_file()
{
    if [ -z "$wow_aid" ]; then
        wow_file_state="$wow_base.state"
        return 0
    fi
    case $wow_aid in
        *[!A-Za-z0-9_-]*) return 1 ;;
    esac
    wow_file_state="$wow_base.$wow_aid.state"
}

wow_last()
{
    wow_prev="off"
    [ -r "$wow_file_state" ] && read -r wow_prev 2> /dev/null < "$wow_file_state"
    [ -n "$wow_prev" ] || wow_prev="off"
}

wow_set_flag()
{
    printf '' 2> /dev/null > "$wow_base.on"
}

# Records wow_key for directory $1 and sets wow_tell when it changed (or when
# there's no state to compare with and it's on). A missing state counts as
# off, the state before any line.
wow_track()
{
    wow_tell=""
    if wow_find "$1"; then wow_on=1; else wow_on=""; fi

    if ! wow_state || ! wow_state_file; then
        wow_tell=$wow_on
        return 0
    fi

    wow_last
    [ "$wow_prev" = "$wow_key" ] && return 0

    wow_lock="$wow_base.lock"
    wow_try=0
    until mkdir -- "$wow_lock" 2> /dev/null; do
        wow_try=$((wow_try + 1))
        if [ "$wow_try" -ge 20 ]; then
            # Fail towards telling Claude, and clear what is most likely a
            # lock left by a killed hook.
            wow_tell=1
            [ -z "$wow_on" ] || wow_set_flag
            rmdir -- "$wow_lock" 2> /dev/null
            return 0
        fi
        sleep 0.05 2> /dev/null
    done

    wow_last
    if [ "$wow_prev" != "$wow_key" ]; then
        printf '%s\n' "$wow_key" 2> /dev/null > "$wow_file_state"
        wow_tell=1
    fi
    [ -z "$wow_on" ] || wow_set_flag
    rmdir -- "$wow_lock" 2> /dev/null
    return 0
}

# Starts a session or a subagent: records the state for the session directory,
# replacing any earlier one, and sets wow_on.
wow_record()
{
    if wow_find "$wow_start"; then wow_on=1; else wow_on=""; fi
    if ! wow_state || ! wow_state_file; then
        return 0
    fi
    printf '%s\n' "$wow_key" 2> /dev/null > "$wow_file_state"
    [ -z "$wow_on" ] || wow_set_flag
    return 0
}

wow_json()
{
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$2"
}

wow_reset()
{
    wow_state || return 1
    rm -rf -- "$wow_base".* 2> /dev/null
    return 0
}

wow_is_wow_name()
{
    case ${1#/} in
        wow-* | *:wow-*) return 0 ;;
    esac
    return 1
}

# Allowed when a touched directory was on, or the session directory is on.
wow_allowed()
{
    if wow_state && [ -e "$wow_base.on" ]; then
        return 0
    fi
    wow_find "$wow_start"
}

wow_mode=${1:-}

wow_start=""
cd -P . 2> /dev/null && wow_start=$PWD

wow_root_ok=""
wow_root=${WORKSPACE_DIR:-${SUDO_HOME:-${HOME:-}}/workspaces}
case $wow_root in
    /*) cd -P -- "$wow_root" 2> /dev/null && wow_root=${PWD%/} && wow_root_ok=1 ;;
esac

case $wow_mode in
    status)
        if wow_find "${2:-$wow_start}"; then
            printf '%s\n' "$wow_line"
            exit 0
        fi
        printf '%s\n' "$wow_line"
        exit 1
        ;;
    session-start)
        wow_read_input
        wow_aid=""
        wow_reset
        wow_record
        [ -z "$wow_on" ] || printf '%s\n' "$wow_line"
        ;;
    subagent-start)
        wow_read_input
        wow_record
        [ -z "$wow_on" ] || wow_json SubagentStart "$wow_line"
        ;;
    pre-tool)
        wow_read_input
        if [ -n "$wow_file" ]; then
            case $wow_file in
                */*) wow_target=${wow_file%/*} ;;
                *) wow_target=. ;;
            esac
            wow_target=${wow_target:-/}
        else
            wow_target=${wow_path:-.}
        fi
        wow_track "$wow_target"
        [ -z "$wow_tell" ] || wow_json PreToolUse "$wow_line"
        ;;
    post-bash)
        wow_read_input
        wow_track "$wow_start"
        [ -z "$wow_tell" ] || wow_json PostToolUse "$wow_line"
        ;;
    pre-skill)
        wow_read_input
        if wow_is_wow_name "$wow_skill" && ! wow_allowed; then
            printf '%s\n' "$WOW_DENY" >&2
            exit 2
        fi
        ;;
    expand)
        wow_read_input
        if wow_is_wow_name "$wow_cname" && ! wow_allowed; then
            wow_cname=${wow_cname#/}
            case $wow_cname in
                *[!A-Za-z0-9._:@+-]*) wow_note="The user typed the command explicitly." ;;
                *) wow_note="The user typed /$wow_cname explicitly." ;;
            esac
            wow_json UserPromptExpansion "Ways of working: off here (no .wow marker). $wow_note"
        fi
        ;;
    session-end)
        wow_read_input
        wow_reset
        ;;
esac
exit 0
