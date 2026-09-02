# Jagger — Ansible Deployment

Automates the [manual installation guide](../MANUAL_INSTALL.md) end to end:
OS packages, MySQL, Apache, Let's Encrypt, PyFF, XMLSecTool, Jagger itself,
its config files, the PHP 8 compatibility fixes, and the SSL vhost.

Targets Debian 13.\* and Ubuntu 24.04/26.04 LTS, matching the [Requirements](../README.md#requirements)
section of the main README.

## What it does *not* automate

- **Creating the admin user.** That's a one-time web form at
  `https://<fqdn>/rr3/setup` — no Ansible module for it. See
  [Setup Jagger Registry](../MANUAL_INSTALL.md#setup-jagger-registry).
- **Dropping your logo file.** Copy your PNG to
  `{{ jagger_install_dir }}/images/` on the target yourself before running the
  playbook (see [Requirements → Others](../README.md#requirements)); the
  playbook only points `site_logo` at its filename.

## Prerequisites

- Ansible >= 2.15 on your control machine.
- A target host meeting the [Requirements](../README.md#requirements) in the
  main README, reachable over SSH with a sudo-capable/root user.
- The target's FQDN already resolving to it via public DNS (needed for the
  Let's Encrypt step), unless you set `letsencrypt_enabled: false`.

Install the required collections:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Setup

1. **Inventory:**
   ```bash
   cp inventory.ini.example inventory.ini
   # edit inventory.ini with your host/IP/SSH user
   ```
2. **Variables:**
   ```bash
   cp group_vars/jagger_servers/vars.yml.example group_vars/jagger_servers/vars.yml
   # edit jagger_fqdn, jagger_admin_email, jagger_git_version, etc.
   ```
3. **Secrets** (DB password, CodeIgniter encryption key, sync password):
   ```bash
   cp group_vars/jagger_servers/vault.yml.example group_vars/jagger_servers/vault.yml
   # generate each value the same way the manual guide does:
   openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
   # paste the results into vault.yml, then encrypt it:
   ansible-vault encrypt group_vars/jagger_servers/vault.yml
   ```

## Running it

```bash
# Full install
ansible-playbook site.yml --ask-vault-pass

# Re-run just one part (any role/tag from tasks/main.yml)
ansible-playbook site.yml --ask-vault-pass --tags letsencrypt
ansible-playbook site.yml --ask-vault-pass --tags jagger

# Skip a part
ansible-playbook site.yml --ask-vault-pass --skip-tags letsencrypt
```

The whole role is idempotent — re-running `site.yml` after a successful run is
safe and is how you pick up variable changes (e.g. after flipping
`jagger_setup_completed`, see below).

### Finishing setup

1. Run the full playbook once. It leaves `rr_setup_allowed = TRUE`.
2. Visit `https://<jagger_fqdn>/rr3/setup` and create the admin user, per
   [Setup Jagger Registry](../MANUAL_INSTALL.md#setup-jagger-registry).
3. Set `jagger_setup_completed: true` in `group_vars/jagger_servers/vars.yml`
   and re-run the playbook (or just `--tags setup-lock`) to lock
   `rr_setup_allowed` back to `FALSE`.

### Updating Jagger

The update flow (`git pull`, `composer install`, schema migration) is in its
own task file and only runs when asked for explicitly:

```bash
ansible-playbook site.yml --ask-vault-pass --tags update
```

Afterwards, sign in and visit `https://<jagger_fqdn>/rr3/update/upgrade` to
run Jagger's own in-app upgrade routine, as in the manual guide's
[Updating Jagger](../MANUAL_INSTALL.md#updating-jagger) section.

## Where this deviates from the manual guide

- **MySQL hardening**: instead of scripting the interactive
  `mysql_secure_installation`, the role removes anonymous users and the `test`
  database directly via `community.mysql` and leaves root authentication on
  the distro default (`unix_socket`) — safer to automate, same end state.
- **TLS**: uses `certbot certonly --apache` (cert only) instead of
  `certbot --apache` (cert + auto-edited vhost), then deploys the SSL vhost
  from our own template. `certbot --apache` rewrites the vhost file in ways
  that aren't idempotent to model in Ansible; templating it ourselves gives
  the same end result and can be safely re-applied.

## Layout

```
ansible/
├── site.yml                   # entry point playbook
├── inventory.ini.example
├── requirements.yml           # collections: community.mysql, community.general
├── group_vars/jagger_servers/
│   ├── vars.yml.example       # non-secret settings
│   └── vault.yml.example      # secrets (DB password, encryption key, syncpass)
└── roles/jagger/
    ├── defaults/main.yml      # all tunables, with sane defaults
    ├── tasks/                 # one numbered file per README section
    ├── templates/             # apt sources, xmlsectool wrapper, SSL vhost
    └── handlers/main.yml
```
