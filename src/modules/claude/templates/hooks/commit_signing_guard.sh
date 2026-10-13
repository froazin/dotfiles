#!/usr/bin/env sh
#
# Claude Code hook: the commit-signing guard. Keeps agents from bypassing git
# commit signing, and makes them stop and report when signing fails (e.g.
# 1Password's Windows Hello prompt timed out because the user is away).
#
# The logic is in commit_signing_guard.py next to this script; this wrapper
# keeps the command in settings.json stable. Without python3 the hook does
# nothing (exit 0 is non-blocking). -I keeps this directory, PYTHONPATH and
# user site-packages off the import path, so nothing can shadow the stdlib.

command -v python3 > /dev/null 2>&1 || exit 0
exec python3 -I "$(dirname "$0")/commit_signing_guard.py"
