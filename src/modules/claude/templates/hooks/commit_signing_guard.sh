#!/usr/bin/env sh
#
# Claude Code commit-signing guard hook. settings.json calls this wrapper so its
# command stays stable: the settings merge replaces hooks by command. Without
# python3 it does nothing (exit 0 is non-blocking). -I keeps this directory,
# PYTHONPATH and user site-packages off the import path, so nothing can shadow
# the stdlib.

command -v python3 > /dev/null 2>&1 || exit 0
exec python3 -I "$(dirname "$0")/commit_signing_guard.py"
