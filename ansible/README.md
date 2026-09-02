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

### 7. Configure secrets

```bash
cp group_vars/jagger_servers/vault.yml.example group_vars/jagger_servers/vault.yml
```

Generate a random value for **each** of the three secrets (run this three times, once per secret):

```bash
openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
```

Then edit the file and paste one generated value into each field:

```bash
nano group_vars/jagger_servers/vault.yml
```

| Variable | Change it to |
|---|---|
| `vault_jagger_db_password` | a generated value (this becomes the MySQL `rr3user` password) |
| `vault_jagger_encryption_key` | a different generated value (CodeIgniter's `encryption_key`) |
| `vault_jagger_syncpass` | a different generated value again (Jagger's `syncpass`) |

Save and exit (`Ctrl+O`, Enter, `Ctrl+X`), then encrypt the file so the secrets are never stored in plain text:

```bash
ansible-vault encrypt group_vars/jagger_servers/vault.yml
```

You'll be asked to set a vault password here — remember it, you'll need it every time you run the playbook.

### 8. Run the playbook

```bash
ansible-playbook site.yml --ask-vault-pass
```

The whole role is idempotent — re-running `site.yml` after a successful run
is safe, and is how you pick up variable changes (e.g. after step 9 below).

You can also target just one part of the install (any tag from
`roles/jagger/tasks/main.yml`):

```bash
ansible-playbook site.yml --ask-vault-pass --tags letsencrypt
ansible-playbook site.yml --ask-vault-pass --skip-tags letsencrypt
```

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
