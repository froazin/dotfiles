---
paths:
  - "src/wsl/**"
---

# WSL cloud-init (`src/wsl/`)

`ubuntu.user-data` is deployed to `%USERPROFILE%\.cloud-init\ubuntu.user-data`
next to a filled-in copy of `ubuntu.meta-data`; both match an instance named
`Ubuntu` (`wsl --install Ubuntu-26.04 --name Ubuntu`). It runs once, on first
boot, and Ubuntu's OOBE (`/usr/lib/wsl/wsl-setup`) waits for it.

## Keep it native

Prefer plain cloud-init modules and semantics over custom scripts. Identifying
values come only from `<InstanceName>.meta-data`, read in the template as
`ds.meta_data.*`. Do not add loaders that read other files from the Windows
side.

## Facts that constrain the design

- The WSL datasource loads exactly one user-data file
  (`<Instance>` > `<ID>-<VERSION_ID>` > `<ID>-all` > `default`) and only
  `<Instance>.meta-data`, which must contain `instance-id`. Nothing is merged
  except Ubuntu Pro's `agent.yaml`, so never add an `ubuntu_pro` key.
- With `agent.yaml` present the datasource wraps a Jinja user-data in
  `#include`; Jinja still renders.
- Jinja runs with `trim_blocks` on and `lstrip_blocks` off: put every
  `{% %}` / `{# #}` tag at column 0, or its indentation is left behind and
  breaks YAML. Never write `{#`, `{{` or `{%` inside embedded shell.
- Undefined meta-data keys are falsy; read them as `ds.meta_data.x or ''`.
  Values rendered into `.gitconfig` go through the `gitval` macro.
- Module order: init stage runs `write_files` and `users`; final stage runs
  packages, deferred `write_files`, then `runcmd` (a `#!/bin/sh` script with
  no `set -e`, so entries are independent). Anything that needs a package or
  a package-created group (`libvirt`) belongs in `runcmd` or deferred
  `write_files`. Listing `libvirt` in `users.groups` makes it an ordinary
  group that takes gid 1000.
- `/etc/wsl.conf` must keep `systemd=true` and `appendWindowsPath=false`
  (otherwise `xdg-open` bypasses `$BROWSER`), and must have no `[user]` or
  `[time]` section: the OOBE writes `[user] default=`, and the time zone
  follows Windows.
- WSL attaches swap before systemd starts; only `swapoff -a` (the
  `disable-swap.service` unit) removes it.
- `qemu-kvm` is a virtual package and `*-hwe` packages conflict with the base
  virt stack; one bad name fails the whole `packages` install. Check
  candidates with `apt-cache policy` before adding packages.
- Never set `power_state` or `package_reboot_if_required`: they restart the
  instance in the middle of the OOBE.
- Run user-scoped installers with `runuser -l <user>` so HOME is the user's.

## Privacy

The repo is public. No usernames, emails, signing keys, hostnames or
`/mnt/c/Users/<name>/` paths in any file here; they belong in the user's
private meta-data. `ubuntu.meta-data` is a template with empty values.

## Validate

Run the `validate-wsl-user-data` skill after every change. Add a mock case
for any new meta-data key or conditional.
