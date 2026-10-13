#!/usr/bin/env sh

ZSH_SOFT_DEPS="fzf git"
ZSH_SOFT_FUNCTIONS="vcs_info compinit add-zsh-hook"
ZSH_SOFT_PLUGINS="/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
ZSH_OPTIONAL_DEPS="op uv pulumi direnv ant"
ZSH_OPTIONAL_SOURCED="nvm:${NVM_DIR:-$HOME/.nvm}/nvm.sh"

zsh_have_function()
{
    zsh -fc "_f=( \${^fpath}/$1(N) ); (( \${#_f} ))" > /dev/null 2>&1
}

zsh_check_soft_deps()
{
    failed="false"

    for cmd in $ZSH_SOFT_DEPS; do
        if command -v "$cmd" > /dev/null 2>&1; then
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

zsh_report_optional_deps()
{
    # Per-user tools (uv, nvm, ...) are normally absent for root by design.
    skipped="warning"
    if is_root; then
        skipped="debug"
    fi

    for cmd in $ZSH_OPTIONAL_DEPS; do
        if command -v "$cmd" > /dev/null 2>&1; then
            log info "Optional integration enabled: $cmd"
        else
            log "$skipped" "Optional integration skipped: $cmd is not installed. Its shell integration stays dormant until it is, no reinstall needed."
        fi
    done

    for entry in $ZSH_OPTIONAL_SOURCED; do
        name="${entry%%:*}"
        file="${entry#*:}"

        if [ -s "$file" ]; then
            log info "Optional integration enabled: $name"
        else
            log "$skipped" "Optional integration skipped: $name is not installed at <$file>. Its shell integration stays dormant until it is, no reinstall needed."
        fi
    done

    return 0
}

zsh_install_config()
{
    log info "Installing zsh configuration."

    templates="$(dirname "$0")/modules/zsh/templates"
    failed="false"

    install_file "$templates/.zshenv" "$HOME/.zshenv" || failed="true"
    install_file "$templates/.zshrc" "$HOME/.zshrc" || failed="true"

    for template in "$templates/.zshrc.d/"*.zsh; do
        [ -f "$template" ] || continue

        install_file "$template" "$HOME/.zshrc.d/$(basename "$template")" || failed="true"
    done

    if [ "$failed" = "true" ]; then
        return 1
    fi

    log info "Zsh configuration installed to <$HOME>."
    return 0
}

zsh_report_login_shell()
{
    if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
        log debug "zsh is already the login shell."
        return 0
    fi

    log warning "zsh is installed and configured but is not your login shell. Run: chsh -s \"$(command -v zsh)\""
    return 0
}

bootstrap()
{
    errors=""

    log info "Bootstrapping zsh configuration."

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
