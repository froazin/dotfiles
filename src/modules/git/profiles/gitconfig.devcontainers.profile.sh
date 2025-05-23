#!/bin/sh

if [ ! -f "$HOME/.gitconfig_setup_complete" ]; then
  (
    (
      # If the gh cli credential helper is set on the host when using a devcontainer,
      # it will result in errors when trying to commit from within the devcontainer as
      # the gh cli will no longer be available. VSCode will automatically handle git
      # authentication for the devcontainer using the host configuration.
      if [ -n "$(git config --global credential.https://github.com.helper)" ]; then
        git config --global --unset-all credential.https://github.com.helper || {
          echo "Failed to unset gh cli credential helper." 
        }
      fi

      if [ -n "$(git config --global credential.https://gist.github.com.helper)" ]; then
        git config --global --unset-all credential.https://gist.github.com.helper || {
          echo "Failed to unset gh cli credential helper." 
        }
      fi

      # Dotfiles are executed before vscode copies the gitconfig file to the container.
      # This means that setting the excludes file in the main bootstrap.sh will
      # prevent the hosts gitconfig from being copied to the container. As a workaround
      # we set the excludes file here, which will be run when the user logs in to the
      # container.
      if [ "$(git config --global core.excludesfile 2>/dev/null)" != "$HOME/.gitignore" ]; then
        git config --global core.excludesfile "$HOME/.gitignore" || {
          echo "Failed to set gitignore file."
        }
      fi

      # VSCode automatically forwards the ssh agent to the devcontainer, so we need to unset
      # the gpg ssh program and command to avoid conflicts.
      if [ -n "$(git config --global gpg.ssh.program)" ]; then
        git config --global --unset-all gpg.ssh.program || {
          echo "Failed to unset gpg ssh program."
        }
      fi

      if [ -n "$(git config --global core.sshCommand)" ]; then
        git config --global --unset-all core.sshCommand || {
          echo "Failed to unset core sshCommand."
        }
      fi

      touch "$HOME/.gitconfig_setup_complete"
    ) >"$HOME/.local/dotfiles_gitconfig.log" 2>&1 &
  )
fi
