#!/usr/bin/env sh

# Everything is graded into two tiers, and NEITHER prevents the
# configuration from being written:
#
#   soft     - the shell works without them but loses real functionality, so
#              they are reported as errors and the module reports failure. The
#              install still completes, and the features light up on the next
#              shell once the dependency is present.
#   optional - nice to have. Reported as warnings only.
#
# The config guards every one of these at runtime, so a missing dependency never
# produces an error on shell startup - it just silently does less.

# Commands. fzf drives CTRL-R / CTRL-T / ALT-C and the `ws` workspace picker;
# git drives the prompt's branch and dirty segments.
ZSH_SOFT_DEPS="fzf git"

# Autoloadable functions, shipped on Debian/Ubuntu as the `zsh-common` package
# and bundled with zsh elsewhere. Probed through zsh's own $fpath rather than a
# package manager so the check is distro-agnostic:
#   vcs_info      - the prompt's entire git segment
#   compinit      - the completion system, and therefore every completion below
#   add-zsh-hook  - shimmed in 00-options.zsh, so this one only degrades
ZSH_SOFT_FUNCTIONS="vcs_info compinit add-zsh-hook"

# Plugin files. Both are apt packages (zsh-autosuggestions,
# zsh-syntax-highlighting) and 90-plugins.zsh sources them only if readable.
ZSH_SOFT_PLUGINS="/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# Auto-enabled when present, skipped with a warning when not.
ZSH_OPTIONAL_DEPS="op uv pulumi direnv"

# Optional tools that are sourced rather than run, so `command -v` cannot see
# them from here. Each is a name and the file 20-tools.zsh sources.
ZSH_OPTIONAL_SOURCED="nvm:${NVM_DIR:-$HOME/.nvm}/nvm.sh"

zsh_have_function() {
    # Resolve an autoloadable function through zsh's own $fpath. Works whether
    # the function tree came from Debian's zsh-common or is bundled with zsh.
    # -f so the user's own config cannot influence the result.
    zsh -fc "_f=( \${^fpath}/$1(N) ); (( \${#_f} ))" >/dev/null 2>&1
}

zsh_check_soft_deps() {
    failed="false"

    for cmd in $ZSH_SOFT_DEPS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log debug "Found soft dependency: $cmd"
        else
            log error "Missing dependency: $cmd is not installed. The configuration will be installed, but the features that rely on it stay inert until it is."
            failed="true"
        fi
    done

    for fn in $ZSH_SOFT_FUNCTIONS; do
        if zsh_have_function "$fn"; then
            log debug "Found zsh function: $fn"
        else
            log error "Missing zsh function: <$fn> was not found in zsh's \$fpath. On Debian/Ubuntu install the 'zsh-common' package. The shell will start, but with reduced functionality."
            failed="true"
        fi
    done

    for plugin in $ZSH_SOFT_PLUGINS; do
        if [ -r "$plugin" ]; then
            log debug "Found plugin: $plugin"
        else
            log error "Missing plugin: <$plugin> not found. Install it for autosuggestions/syntax highlighting; the shell works without it."
            failed="true"
        fi
    done

    if [ "$failed" = "true" ]; then
        return 1
    fi

    return 0
}

zsh_report_optional_deps() {
    for cmd in $ZSH_OPTIONAL_DEPS; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log info "Optional integration enabled: $cmd"
        else
            log warning "Optional integration skipped: $cmd is not installed. Its shell integration stays dormant until it is, no reinstall needed."
        fi
    done

    for entry in $ZSH_OPTIONAL_SOURCED; do
        name="${entry%%:*}"
        file="${entry#*:}"

        if [ -s "$file" ]; then
            log info "Optional integration enabled: $name"
        else
            log warning "Optional integration skipped: $name is not installed at <$file>. Its shell integration stays dormant until it is, no reinstall needed."
        fi
    done

    return 0
}

zsh_install_file() {
    # Copy a single template into $HOME, warning before clobbering anything that
    # is already there and refusing to write through a symlink.
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

    if [ -f "$dest" ]; then
        if cmp -s "$src" "$dest"; then
            log debug "<$dest> is already up to date."
            return 0
        fi

        log warning "Existing file <$dest> was found, it will be overwritten."
    fi

    if ! [ -d "$(dirname "$dest")" ]; then
        mkdir -p "$(dirname "$dest")" >/dev/null 2>&1 || {
            log error "Failed to create directory <$(dirname "$dest")>."
            return 1
        }
    fi

    cp --force "$src" "$dest" >/dev/null 2>&1 || {
        log error "Failed to write <$dest>."
        return 1
    }

    log debug "Installed <$dest>."
    return 0
}

zsh_install_config() {
    log info "Installing zsh configuration."

    templates="$(dirname "$0")/modules/zsh/templates"
    failed="false"

    zsh_install_file "$templates/.zshenv" "$HOME/.zshenv" || failed="true"
    zsh_install_file "$templates/.zshrc" "$HOME/.zshrc" || failed="true"

    # The numbered drop-ins. Load order is encoded in the filenames, so the
    # whole directory is copied verbatim rather than cherry-picked.
    for template in "$templates/.zshrc.d/"*.zsh; do
        [ -f "$template" ] || continue

        zsh_install_file "$template" "$HOME/.zshrc.d/$(basename "$template")" || failed="true"
    done

    if [ "$failed" = "true" ]; then
        return 1
    fi

    log info "Zsh configuration installed to <$HOME>."
    return 0
}

zsh_report_login_shell() {
    # Deliberately does not run chsh: changing a login shell is the user's call,
    # not an installer's side effect.
    if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
        log debug "zsh is already the login shell."
        return 0
    fi

    log warning "zsh is installed and configured but is not your login shell. Run: chsh -s \"$(command -v zsh)\""
    return 0
}

bootstrap() {
    errors=""

    log info "Bootstrapping zsh configuration."

    # Soft dependencies are reported first so the reason for a failed module is
    # visible above the install output, but they never short-circuit it - the
    # configuration is written either way.
    zsh_check_soft_deps || errors="true"

    zsh_report_optional_deps || {
        log error "Failed to evaluate optional zsh integrations."
        errors="true"
    }

    zsh_install_config || {
        log error "Failed to install zsh configuration."
        errors="true"
    }

    zsh_report_login_shell || {
        log error "Failed to check the login shell."
        errors="true"
    }

    if [ -n "$errors" ]; then
        log warning "Zsh configuration completed with errors."
        return 1
    fi

    log info "Zsh configuration bootstrapped successfully."
    return 0
}
