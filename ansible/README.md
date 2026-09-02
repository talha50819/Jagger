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

- A control machine to run `ansible-playbook` from (your laptop is fine — it
  does not need to be the Jagger server itself).
- A target host meeting the [Requirements](../README.md#requirements) in the
  main README, reachable over SSH with a sudo-capable/root user.
- The target's FQDN already resolving to it via public DNS (needed for the
  Let's Encrypt step), unless you set `letsencrypt_enabled: false`.

## Installation

Run these in order, on your **control machine**.

### 1. Get this repo

```bash
git clone https://github.com/talha50819/Jagger.git
cd Jagger/ansible
```

Every command below is run from inside this `ansible/` folder.

### 2. Install Ansible

```bash
sudo apt update
sudo apt install ansible sshpass --no-install-recommends
ansible --version   # confirm ansible-core >= 2.15
```

If your distro ships an older `ansible-core` than 2.15, install it via `pipx`
instead:

```bash
sudo apt install pipx --no-install-recommends
pipx install --include-deps ansible
pipx ensurepath
```

### 3. Verify SSH access to the target

```bash
ssh <ansible_user>@<target-host> "sudo whoami"   # should print "root"
```

### 4. Install the required Ansible collections

```bash
ansible-galaxy collection install -r requirements.yml
```

> **Shortcut — skip steps 5–7 entirely.** Those steps just get three pieces
> of information (target host, FQDN, admin email) into files, and secrets are
> already auto-generated (step 7). If you're deploying to one server and
> don't need reusable config, skip straight to step 8 and pass everything
> inline instead:
> ```bash
> ansible-playbook site.yml \
>   -i "jagger.example.org," \
>   -e ansible_host=203.0.113.10 \
>   -e ansible_user=root \
>   -e jagger_fqdn=jagger.example.org \
>   -e jagger_admin_email=admin@example.org
> ```
> Re-run the same command later to update variables or re-apply the role —
> it's the same idempotent playbook either way. Keep reading below for the
> file-based approach, which is easier to re-run, tweak, or hand to someone
> else without retyping the whole command.

### 5. Configure the inventory

```bash
cp inventory.ini.example inventory.ini
nano inventory.ini
```

It's a single line — change these three things:

```ini
[jagger_servers]
jagger.example.org ansible_host=203.0.113.10 ansible_user=root ansible_python_interpreter=/usr/bin/python3
```

| Field | Change it to |
|---|---|
| `jagger.example.org` | your Jagger server's real FQDN |
| `ansible_host=203.0.113.10` | its real IP address (or hostname) |
| `ansible_user=root` | the SSH user you connect as (leave as `root` if that's how you SSH in) |

Save and exit (`Ctrl+O`, Enter, `Ctrl+X`).

### 6. Configure variables

```bash
cp group_vars/jagger_servers/vars.yml.example group_vars/jagger_servers/vars.yml
nano group_vars/jagger_servers/vars.yml
```

What to change:

| Variable | Change it to |
|---|---|
| `jagger_fqdn` | same FQDN you used in `inventory.ini` |
| `jagger_admin_email` | a real email address (used for Let's Encrypt renewal notices) |
| `jagger_git_version` | leave as `1.x-stable` unless you need a specific branch/tag |
| `jagger_add_hosts_entry` | leave `false` unless this is a lab box with no real DNS yet |
| `apt_mirror_enabled` | leave `false` unless you want the GARR mirrors from the main README |
| `jagger_site_logo` | leave as `logo-default.png` unless you're using your own logo filename |
| `jagger_setup_completed` | leave `false` for now — you'll flip this in step 9 |

Save and exit (`Ctrl+O`, Enter, `Ctrl+X`).

### 7. Secrets — nothing to do (auto-generated)

The DB password, CodeIgniter encryption key, and sync password need to be
*some* random 64-character string — there's no reason to type or paste them
by hand. The playbook generates all three itself on first run and saves them
to `.secrets/<jagger_fqdn>/` next to this README (mode `0600`, git-ignored),
then reuses those same values on every re-run so nothing rotates underneath
you.

**Back up that `.secrets/` folder** — if you lose it, a re-run generates new
secrets, which breaks existing logins/sessions until you update
`database.php`/`config.php` on the target to match.

> **Optional — pin your own values instead** (e.g. to match an existing
> database password): copy `group_vars/jagger_servers/vault.yml.example` to
> `vault.yml`, fill in the three `vault_jagger_*` fields, encrypt it with
> `ansible-vault encrypt group_vars/jagger_servers/vault.yml`, and run the
> playbook with `--ask-vault-pass`. Anything set there overrides the
> auto-generated value.

### 8. Run the playbook

```bash
ansible-playbook site.yml
```

The whole role is idempotent — re-running `site.yml` after a successful run
is safe, and is how you pick up variable changes (e.g. after step 9 below).

You can also target just one part of the install (any tag from
`roles/jagger/tasks/main.yml`):

```bash
ansible-playbook site.yml --tags letsencrypt
ansible-playbook site.yml --skip-tags letsencrypt
```

(If you used the optional vault.yml from step 7, add `--ask-vault-pass` to
every `ansible-playbook` command from here on.)

### 9. Finish setup

1. Visit `https://<jagger_fqdn>/rr3/setup` and create the admin user, per
   [Setup Jagger Registry](../MANUAL_INSTALL.md#setup-jagger-registry).
2. Set `jagger_setup_completed: true` in `group_vars/jagger_servers/vars.yml`
   and re-run the playbook (or just `--tags setup-lock`) to lock
   `rr_setup_allowed` back to `FALSE`.

## Updating Jagger

The update flow (`git pull`, `composer install`, schema migration) is in its
own task file and only runs when asked for explicitly:

```bash
ansible-playbook site.yml --tags update
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
├── .gitignore                 # ignores inventory.ini, vars.yml, vault.yml, .secrets/
├── .secrets/                  # auto-generated secrets (created on first run)
├── group_vars/jagger_servers/
│   ├── vars.yml.example       # non-secret settings
│   └── vault.yml.example      # optional: pin your own secrets instead of auto-generating
└── roles/jagger/
    ├── defaults/main.yml      # all tunables, with sane defaults
    ├── tasks/                 # one numbered file per README section
    ├── templates/             # apt sources, xmlsectool wrapper, SSL vhost
    └── handlers/main.yml
```
