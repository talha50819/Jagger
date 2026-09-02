# Jagger Federation Registry

[Jagger](http://jagger.heanet.ie) is developed by HEAnet to manage the Edugate multiparty SAML federation. Other organisations use Jagger to manage their federations, but it can also be used to manage the web-of-trust for a single entity. Additionally, it can be used as a GUI for the Shibboleth SAML Identity Provider ([Shibboleth](https://www.shibboleth.net)).

> [!NOTE]
> **This is not the official installation guide.** HEAnet's official documentation
> (see [Documentation](#documentation)) targets older, EOL package and OS versions.
> This repo's [Manual Installation](MANUAL_INSTALL.md) and
> [Ansible](ansible/README.md) guides have been reworked to target current
> releases — Debian 13 / Ubuntu 24.04+, PHP 8.4/8.5, Let's Encrypt instead of
> self-signed certs, `utf8mb4` — plus a few extras like an automated
> Ansible-based install path. See [Requirements](#requirements) below for the
> full current baseline.

## Features

1. Synchronise SAML metadata from another federation.
2. Create and manage a federation.
3. Create a single circle of trust containing metadata of all entities that your organisation participates in via multiple federations.
4. GUI to manage the attribute policy of identity providers based on the Shibboleth SAML implementation.
5. Filter the `RequestedAttribute`s of a SAML service provider to allow an IdP to release attributes to such providers based on a policy set in the Jagger GUI.
6. Create and edit metadata of individual entities.
7. Notification subsystem with subscription options.

---

## Requirements

### Hardware
- **CPU**: 4 Core (64-bit)
- **RAM**: 8 GB
- **HDD**: 50 GB
- **OS**: Debian 13.* or Ubuntu 24.04 LTS / 26.04 LTS

### Software
- **Apache Web Server**: 2.4
- **OpenSSL**: 3.5
- **PHP**: 8.4 / 8.5
- **Java**: Default JDK (Required for XMLSecTool)
- **Python**: 3.x with `venv` and `pip` (Required for PyFF)
- **Shibboleth Service Provider**: 5 *(Optional)*

### Others
- **Domain**: A Fully Qualified Domain Name (FQDN) with public DNS resolution pointing to this server.
- **Logo**: 
  - Size: 350px wide × 64px high (or 146px wide × 64px high)
  - Format: PNG
  - Style: Transparent background

---

## Installation

Pick one:

- **[Manual Installation](MANUAL_INSTALL.md)** — full step-by-step walkthrough (Apache, MySQL, Let's Encrypt, PyFF, XMLSecTool, Jagger itself, PHP 8 compatibility fixes).
- **[Automated Installation (Ansible)](ansible/README.md)** — an idempotent Ansible role that runs the same steps for you.

Both cover the same install and end at the same place: the one-time [admin setup wizard](MANUAL_INSTALL.md#setup-jagger-registry) at `https://<your-fqdn>/rr3/setup`.

---

## Documentation

Official HEAnet administration documentation (application usage, not this
install guide) is available at:  
[https://jagger.heanet.ie/jaggerdocadmin/index.html](https://jagger.heanet.ie/jaggerdocadmin/index.html)

---

## Authors & Thanks

- **Install Guide Author**: Muhammad Talha Siddiqui — updated and maintained independently of HEAnet, to track current OS/package versions.
- **Project Repository**: [Edugate/Jagger](https://github.com/Edugate/Jagger)
- **Special Thanks**: [@janul](https://github.com/janul) and the HEAnet/Edugate community for their ongoing support and development.
