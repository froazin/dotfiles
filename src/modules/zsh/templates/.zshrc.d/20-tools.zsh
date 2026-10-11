#!/usr/bin/env zsh
# shellcheck shell=bash
#
# External tool hooks.
#
# Both of these register ZLE widgets, so they must load before
# zsh-syntax-highlighting (90-plugins.zsh), which wraps every widget that
# exists at the moment it is sourced.

# direnv prepends _direnv_hook to precmd_functions and chpwd_functions itself,
# so it always runs before the prompt's vcs_info hook regardless of load order.
# That is what we want: direnv is what activates the virtualenv the prompt then
# renders.
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
  DIRENV_WARN_TIMEOUT=60s
  export DIRENV_WARN_TIMEOUT
fi

# CTRL-R history, CTRL-T file paste, ALT-C cd.
#
# `fzf --zsh` (fzf >= 0.48) emits key bindings and completion together, built
# from the installed binary. It replaces the older, now-deprecated approach of
# sourcing /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh.
#
# Note: CTRL-R reads the in-memory history via fc, so it still works fully
# despite history never being written to disk (see 00-options.zsh).
if (( $+commands[fzf] )); then
  _fzf_version=$(fzf --version | cut -d' ' -f1)
  _fzf_major_version=$(echo "$_fzf_version" | cut -d. -f1)
  _fzf_minor_version=$(echo "$_fzf_version" | cut -d. -f2)

  if [[ $_fzf_major_version -eq 0 && $_fzf_minor_version -ge 48 ]]; then
    source <(fzf --zsh)
  else
    _fzf_key_bindings="/usr/share/doc/fzf/examples/key-bindings.zsh"
    _fzf_completion="/usr/share/doc/fzf/examples/completion.zsh"

    if [[ -f $_fzf_key_bindings ]]; then
      source "$_fzf_key_bindings"
    fi

    if [[ -f $_fzf_completion ]]; then
      source "$_fzf_completion"
    fi
  fi
fi
