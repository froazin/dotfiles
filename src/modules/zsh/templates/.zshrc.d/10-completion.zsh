#!/usr/bin/env zsh
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
  # Outside fpath, so compinit never sees it.
  local failed="$ZSH_COMPLETION_DIR/.failed/$name"

  [[ -n $bin && -x $bin ]] || return 2          # tool not installed
  if (( ! force )); then
    [[ -f $file && ! $bin -nt $file ]] && return 1      # already current
    # Don't retry a generator that failed for this same binary on every
    # startup (e.g. Apache Ant answering to `ant`); zshup forces a retry.
    [[ -f $failed && ! $bin -nt $failed ]] && return 3
  fi

  local tmp="$file.new.$$"
  # Run from a directory we own, so a tool that reads its working directory
  # (Apache Ant parses ./build.xml) never acts on the project the shell opened in.
  if ( cd -q "$ZSH_COMPLETION_DIR" && eval "$generator" ) > "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
    # Give a tool a chance to patch its own generated completion. Runs here so
    # the fix is reapplied automatically on every regeneration, including zshup.
    (( $+functions[_zcache_patch_$name] )) && "_zcache_patch_$name" "$tmp"
    mv -f "$tmp" "$file"
    rm -f "$failed"
    return 0                                    # regenerated
  fi
  rm -f "$tmp"
  mkdir -p "${failed:h}" && : >| "$failed"
  return 3                                      # generation failed
}

# ---------------------------------------------------------------------------
# uv: fix completion of the command `uv run` is about to execute.
# ---------------------------------------------------------------------------
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
    if [[ -n $venv && -d $bindir ]]; then
      bins=( $bindir/*(N-*:t) )
      bins=( ${bins:#(activate*|deactivate*|*.bat|*.ps1|*.csh|*.fish|*.nu)} )
    fi
  fi

  _alternative \
    "project-commands:project command:{_describe -t project-commands 'project command' bins}" \
    'commands:command: _command_names -e' \
    'files:file: _files'
}

# Optional tool completions.
typeset -gA ZSH_OPTIONAL_COMPLETIONS=(
  uv     'uv generate-shell-completion zsh'
  uvx    'uvx --generate-shell-completion zsh'
  op     'op completion zsh'
  pulumi 'pulumi gen-completion zsh'
  ant    'ant @completion zsh'
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
zmodload zsh/complist # provides the menuselect keymap

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
