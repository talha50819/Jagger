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

Two different failures show up as the same "Permission denied" message:

**If the plain `ssh` command above worked (it prompted you for a password),
but `ansible-playbook` fails** — Ansible doesn't prompt for a password unless
told to. Either:
- **Copy your key over once (recommended):**
  ```bash
  ssh-copy-id <ansible_user>@<target-host>
  ```
  Then step 5's `ansible-playbook` command needs nothing extra.
- **Or keep using a password:** add `-k` to every `ansible-playbook` command
  from step 5 onward (that's what `sshpass`, installed in step 2, is for) —
  it'll prompt for the SSH password before each run:
  ```bash
  ansible-playbook site.yml $JAGGER_ARGS -k
  ```

**If even the plain `ssh root@<target-host>` command above is rejected, no
matter the password** — the target almost certainly has direct root SSH
login disabled (`PermitRootLogin no`, the **default on modern Ubuntu/Debian**
— check with `grep -i PermitRootLogin /etc/ssh/sshd_config*` on the target).
No root password will ever work there. Use your normal, sudo-capable login
user instead (e.g. `user`, not `root`) and let Ansible's `become: true`
(already set) escalate to root via `sudo`:

```bash
ssh user@<target-host> "sudo whoami"   # should still print "root"
```

Set `ansible_user=user` in step 5's `JAGGER_ARGS` instead of `root`. If that
user's `sudo` itself asks for a password, also add `-K` (`--ask-become-pass`)
alongside `-k` on every `ansible-playbook` command — you'll get two separate
password prompts, one for SSH and one for `sudo`.

**If `-k -K` instead fails with `Timeout waiting for privilege escalation
prompt`** — Ansible ran `sudo` without a real terminal attached (it doesn't
allocate one by default), and most systems' `sudo` refuses to show its
password prompt without one (`Defaults requiretty` in `/etc/sudoers`, or
just how `sudo` behaves over a plain SSH command). Fix it by giving your
Ansible user passwordless `sudo` — the standard approach for automation
accounts, and it sidesteps this prompt entirely, so `-K` is no longer
needed either:

```bash
echo "user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible-user
sudo chmod 440 /etc/sudoers.d/ansible-user
```

(Replace `user` with the real username in both the command and the file's
content.) Drop `-K` from every `ansible-playbook` command from here on;
keep `-k` unless you've also set up `ssh-copy-id`.

### 4. Install the required Ansible collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 5. Run the playbook

No files to edit — everything host-specific is passed on the command line,
and the DB password, CodeIgniter encryption key, and sync password are
generated automatically on first run and saved to `.secrets/<jagger_fqdn>/`
next to this file (mode `0600`, git-ignored), then reused on every re-run so
nothing rotates underneath you.

Set the four values once per shell session, then reuse them:

```bash
JAGGER_ARGS='-i jagger.example.org, -e ansible_host=203.0.113.10 -e ansible_user=user -e jagger_fqdn=jagger.example.org -e jagger_admin_email=admin@example.org'
```

| Value | Change it to |
|---|---|
| `jagger.example.org` (both places) | your Jagger server's real FQDN |
| `ansible_host=203.0.113.10` | its real IP address (or hostname) |
| `ansible_user=user` | the account you SSH in as — your normal sudo-capable login user on most systems (see step 3 if you're unsure whether that's `root` or not) |
| `jagger_admin_email=admin@example.org` | a real email address (used for Let's Encrypt renewal notices) |

Then run the playbook — add `-k` and/or `-K` here if step 3 told you to
(logging in as a non-root user with password-based `sudo` needs **both**:
`-k` for the SSH password, `-K` for the separate `sudo` password prompt):

```bash
ansible-playbook site.yml $JAGGER_ARGS -k -K
```

The whole role is idempotent — re-run the same command any time (e.g. to
change a value), and target just one part with `--tags`/`--skip-tags` (any
tag from `roles/jagger/tasks/main.yml`):

```bash
ansible-playbook site.yml $JAGGER_ARGS -k -K --tags letsencrypt
ansible-playbook site.yml $JAGGER_ARGS -k -K --skip-tags letsencrypt
```

(`-k` and `-K` are independent — drop `-k` once you've set up key-based SSH
with `ssh-copy-id`, and drop `-K` once you've set up passwordless `sudo`;
see step 3 for both.)

> Optional — pin your own secret values instead (e.g. to match an existing
> database password): copy `group_vars/jagger_servers/vault.yml.example` to
> `vault.yml`, fill in the three `vault_jagger_*` fields, encrypt it with
> `ansible-vault encrypt group_vars/jagger_servers/vault.yml`, and add
> `--ask-vault-pass` to every command above.

### 6. Finish setup

1. Visit `https://<jagger_fqdn>/rr3/setup` and create the admin user, per
   [Setup Jagger Registry](../MANUAL_INSTALL.md#setup-jagger-registry).
2. Re-run with `jagger_setup_completed` set to lock `rr_setup_allowed` back
   to `FALSE` (same `-k -K` rules as step 5 apply to every command below):
   ```bash
   ansible-playbook site.yml $JAGGER_ARGS -k -K -e jagger_setup_completed=true
   ```

## Updating Jagger

The update flow (`git pull`, `composer install`, schema migration) is in its
own task file and only runs when asked for explicitly:

```bash
ansible-playbook site.yml $JAGGER_ARGS -k -K --tags update
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
├── inventory.ini.example      # unused by the -e/-i one-liner flow; a reference if you want a persistent inventory file instead
├── requirements.yml           # collections: community.mysql, community.general
├── .gitignore                 # ignores inventory.ini, vars.yml, vault.yml, .secrets/
├── .secrets/                  # auto-generated secrets (created on first run)
├── group_vars/jagger_servers/
│   ├── vars.yml.example       # unused by the -e/-i one-liner flow; every var here can also be passed as -e instead
│   └── vault.yml.example      # optional: pin your own secrets instead of auto-generating
└── roles/jagger/
    ├── defaults/main.yml      # all tunables, with sane defaults
    ├── tasks/                 # one numbered file per README section
    ├── templates/             # apt sources, xmlsectool wrapper, SSL vhost
    └── handlers/main.yml
```
