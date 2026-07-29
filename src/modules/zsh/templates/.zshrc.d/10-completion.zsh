#!/usr/bin/env zsh
# shellcheck shell=zsh
#
# Completion system: fpath, cached tool completions, compinit, styling.

# ---------------------------------------------------------------------------
# fpath
# ---------------------------------------------------------------------------
ZSH_COMPLETION_DIR="$HOME/.local/share/zsh/site-functions"
[[ -d $ZSH_COMPLETION_DIR ]] || mkdir -p "$ZSH_COMPLETION_DIR"

fpath=(
  "$ZSH_COMPLETION_DIR"
  /usr/share/zsh/site-functions
  $fpath
)

# ---------------------------------------------------------------------------
# Cached tool completions.
# ---------------------------------------------------------------------------
zcache_completion() {
  emulate -L zsh
  local force=0
  [[ $1 == -f ]] && { force=1; shift }

  local name=$1 generator=$2 bin=$3
  local file="$ZSH_COMPLETION_DIR/_$name"

  [[ -n $bin && -x $bin ]] || return 2          # tool not installed
  if (( ! force )) && [[ -f $file && ! $bin -nt $file ]]; then
    return 1                                    # already current
  fi

  local tmp="$file.new.$$"
  if eval "$generator" > "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
    # Give a tool a chance to patch its own generated completion. Runs here so
    # the fix is reapplied automatically on every regeneration, including zshup.
    (( $+functions[_zcache_patch_$name] )) && "_zcache_patch_$name" "$tmp"
    mv -f "$tmp" "$file"
    return 0                                    # regenerated
  fi
  rm -f "$tmp"
  return 3                                      # generation failed
}

# ---------------------------------------------------------------------------
# uv: fix completion of the command `uv run` is about to execute.
#
# uv's clap-generated zsh completion declares that positional as
#   "*::external_command:_default"
# and _default is plain file completion. So in a project containing an
# ansible.cfg, `uv run ansible-p<TAB>` completes to `ansible-playbook`'s
# neighbour ansible.cfg, and never offers .venv/bin/ansible-playbook - the
# thing uv would actually run. (uv's bash completion has the same gap; it uses
# `compgen -f`.) Swap that one action for a completer that knows about the
# project environment. Everything else in the generated file is untouched, so
# _arguments still does all of uv's option parsing.
_zcache_patch_uv()  { sed -i 's/::external_command:_default/::external_command:_uv_run_command/g' "$1" }
_zcache_patch_uvx() { _zcache_patch_uv "$1" }

_uv_run_command() {
  local -a bins
  local venv bindir dir

  # Project-environment commands only make sense for `uv run`. `uvx` and
  # `uv tool run` execute published tools, not things in the local venv.
  if [[ $curcontext == *:uv-command-run:* ]]; then
    if [[ -n $VIRTUAL_ENV ]]; then
      venv=$VIRTUAL_ENV
    elif [[ -n $UV_PROJECT_ENVIRONMENT ]]; then
      venv=$UV_PROJECT_ENVIRONMENT
    else
      # Walk up for the nearest .venv, the way uv discovers a project.
      dir=$PWD
      while true; do
        [[ -d $dir/.venv/bin ]] && { venv=$dir/.venv; break }
        [[ $dir == / || -z $dir ]] && break
        dir=${dir:h}
      done
    fi

    bindir=$venv/bin
    # (N) no-match-is-empty, (-) follow symlinks, (*) executable plain files,
    # (:t) basename only.
    if [[ -n $venv && -d $bindir ]]; then
      bins=( $bindir/*(N-*:t) )
      # Drop the shell-activation shims and the Windows/other-shell variants -
      # `uv run activate.ps1` is never what anyone means. python/python3 stay.
      bins=( ${bins:#(activate*|deactivate*|*.bat|*.ps1|*.csh|*.fish|*.nu)} )
    fi
  fi

  _alternative \
    "project-commands:project command:{_describe -t project-commands 'project command' bins}" \
    'commands:command: _command_names -e' \
    'files:file: _files'
}

# Optional tool completions.
#
# Every tool here is OPTIONAL: if the command is not installed its entry is
# skipped and the shell starts normally. Nothing warns at startup - a shell that
# nags on every launch is worse than a missing completion. The dotfiles
# installer warns once at install time, and `zshup` reports skipped tools.
#
# Keep this as the single registry: `zshup` (60-maintenance.zsh) iterates the
# same array to force a regeneration.
#
# uv exposes the generator as a subcommand, but uvx exposes it as a hidden
# top-level FLAG - `uvx generate-shell-completion` makes uvx try to resolve that
# as a PyPI package instead.
#
# pulumi's is a Cobra bash-completion-v1 script that sed-converts itself for zsh
# and calls `autoload -U +X bashcompinit && bashcompinit` internally, so no
# bashcompinit setup is needed here. It is slower and less rich than a native
# completion, but it is what pulumi ships.
typeset -gA ZSH_OPTIONAL_COMPLETIONS=(
  uv     'uv generate-shell-completion zsh'
  uvx    'uvx --generate-shell-completion zsh'
  op     'op completion zsh'
  pulumi 'pulumi gen-completion zsh'
)

for _zc_tool in ${(ko)ZSH_OPTIONAL_COMPLETIONS}; do
  zcache_completion "$_zc_tool" "${ZSH_OPTIONAL_COMPLETIONS[$_zc_tool]}" ${commands[$_zc_tool]}
done
unset _zc_tool

# ---------------------------------------------------------------------------
# compinit
# ---------------------------------------------------------------------------
ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
[[ -d ${ZSH_COMPDUMP:h} ]] || mkdir -p "${ZSH_COMPDUMP:h}"

# compinit lives in zsh's function tree (Debian: zsh-common). Without it there
# is no completion system at all, so everything below - compdef, zstyle
# ':completion:*', the menuselect keymap - would be meaningless. Skip the lot.
if zsh_have_function compinit; then
  autoload -Uz compinit
  if [[ -n ${ZSH_COMPDUMP}(#qN.mh+24) || ! -f $ZSH_COMPDUMP ]]; then
    compinit -d "$ZSH_COMPDUMP"
  else
    compinit -C -d "$ZSH_COMPDUMP"
  fi
  ZSH_COMPINIT_OK=1
else
  ZSH_COMPINIT_OK=0
fi

# /usr/bin/docker here is the podman-docker shim, and `docker completion zsh`
# emits a file that registers `podman`, not `docker`. Reuse podman's real
# completion for the docker command name instead.
if (( ZSH_COMPINIT_OK )) && [[ -e /usr/bin/docker ]] && (( $+functions[_podman] || $+_comps[podman] )); then
  compdef _podman docker
fi

# ---------------------------------------------------------------------------
# Completion behaviour and appearance
# ---------------------------------------------------------------------------
zmodload zsh/complist                   # provides the menuselect keymap

zstyle ':completion:*' menu select

# Try exact, then case-insensitive, then partial-word (f/b/foo -> foo/bar/baz),
# then substring - each only if the previous produced nothing.
zstyle ':completion:*' matcher-list \
  '' \
  'm:{a-zA-Z}={A-Za-z}' \
  'r:|[._-]=* r:|=*' \
  'l:|=* r:|=*'

zstyle ':completion:*' completer _extensions _complete _approximate

# Group matches by type and label each group.
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{#21bfd3}-- %d --%f'
zstyle ':completion:*:messages'     format '%F{#cccccc}-- %d --%f'
zstyle ':completion:*:warnings'     format '%F{#d54a35}-- no matches --%f'
zstyle ':completion:*' verbose yes

# Colour filenames in the completion list using LS_COLORS.
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

# Cache slow completions (apt, systemctl, ...).
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"

zstyle ':completion:*' special-dirs false   # don't offer . and .. as matches
zstyle ':completion:*' squeeze-slashes true

# Useful process lists for kill/killall.
zstyle ':completion:*:*:kill:*:processes' \
  list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# Navigate the completion menu with the arrow keys or hjkl.
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
