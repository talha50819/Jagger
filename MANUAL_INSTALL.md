# Manual Installation

Step-by-step walkthrough for installing Jagger by hand on Debian/Ubuntu. See
the [main README](README.md#requirements) for hardware/software requirements
before starting, or use the [Ansible role](ansible/README.md) instead to
automate all of this.

## Table of Contents

1. [Important Notes](#important-notes)
2. [Configure the Environment](#configure-the-environment)
3. [Configure APT Mirror](#configure-apt-mirror)
4. [Install Dependencies](#install-dependencies)
5. [Install MySQL Server](#install-mysql-server)
6. [Install Apache Web Server](#install-apache-web-server)
7. [Configure Apache Web Server (HTTP)](#configure-apache-web-server-http)
8. [Install and Configure Let's Encrypt (HTTPS)](#install-and-configure-lets-encrypt-https)
9. [Install PyFF (Metadata Processing)](#install-pyff-metadata-processing)
10. [Install XMLSecTool (Metadata Validation)](#install-xmlsectool-metadata-validation)
11. [Install Jagger](#install-jagger)
12. [Configure Jagger Database](#configure-jagger-database)
13. [Configure Jagger](#configure-jagger)
14. [Populate Database Tables](#populate-database-tables)
15. [PHP Compatibility & Code Fixes](#php-compatibility--code-fixes)
16. [Finalize Apache Jagger VirtualHost](#finalize-apache-jagger-virtualhost)
17. [Setup Jagger Registry](#setup-jagger-registry)
18. [Updating Jagger](#updating-jagger)

---

## Important Notes

> [!WARNING]
> This HOWTO uses `example.org` and `jagger.example.org` as example values. 
> Please remember to **replace all occurrences** of:
> - `example.org` with your actual domain name.
> - `jagger.example.org` with the Fully Qualified Domain Name (FQDN) of your Jagger instance.

---

## Configure the Environment

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Ensure your firewall **is not blocking** traffic on ports **443** and **80** for the Jagger server.
3. Set the server hostname:
   > [!CAUTION]
   > Replace `jagger.example.org` with your SP FQDN and `<HOSTNAME>` with the Jagger server hostname.
   ```bash
   echo "<YOUR-SERVER-IP-ADDRESS> jagger.example.org <HOSTNAME>" >> /etc/hosts
   hostnamectl set-hostname <HOSTNAME>
   ```

---

## Configure APT Mirror

- [Debian Mirror List](https://www.debian.org/mirror/list)
- [Ubuntu Mirror List](https://launchpad.net/ubuntu/+archivemirrors)

*Example using the Consortium GARR Italian mirrors:*

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Change the default mirror:

   **For Debian (Deb822 format):**
   ```bash
   sudo bash -c '. /etc/os-release; cat > /etc/apt/sources.list.d/garr.sources <<EOF
   Types: deb deb-src
   URIs: https://debian.mirror.garr.it/debian/
   Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
   Components: main contrib non-free non-free-firmware
   Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
   
   Types: deb deb-src
   URIs: https://debian.mirror.garr.it/debian-security/
   Suites: $VERSION_CODENAME-security
   Components: main contrib non-free non-free-firmware
   Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
   EOF'
   ```

   **For Ubuntu:**
   ```bash
   sudo bash -c '. /etc/os-release; cat > /etc/apt/sources.list.d/garr.sources <<EOF
   Types: deb deb-src
   URIs: https://ubuntu.mirror.garr.it/ubuntu/
   Suites: $VERSION_CODENAME $VERSION_CODENAME-updates $VERSION_CODENAME-backports
   Components: main restricted universe multiverse
   Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
   
   Types: deb deb-src
   URIs: https://ubuntu.mirror.garr.it/ubuntu/
   Suites: $VERSION_CODENAME-security
   Components: main restricted universe multiverse
   Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
   EOF'
   ```

3. Update packages:
   ```bash
   apt update && apt-get upgrade -y --no-install-recommends
   ```

---

## Install Dependencies

```bash
sudo apt install fail2ban nano wget ca-certificates openssl ntpsec git unzip --no-install-recommends
```

---

## Install MySQL Server

```bash
sudo apt install default-mysql-server --no-install-recommends
```

### Protect MySQL Server
```bash
sudo mysql_secure_installation
```

**On Ubuntu:**
- Setup VALIDATE PASSWORD component? **No**
- Remove anonymous users? **Yes**
- Disallow root login remotely? **Yes**
- Remove test database and access to it? **Yes**
- Reload privilege tables now? **Yes**

**On Debian:**
- Root password: **Leave empty or set a desired value**
- Switch to unix_socket: **Y**
- Change the root password? **N**
- Remove anonymous users? **Y**
- Disallow root login remotely? **Y**
- Remove test database and access to it? **Y**
- Reload privilege tables now? **Y**

---

## Install Apache Web Server

```bash
sudo apt install apache2
```

---

## Configure Apache Web Server (HTTP)

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Create the DocumentRoot:
   ```bash
   mkdir -p /var/www/html/$(hostname -f)
   chown -R www-data:www-data /var/www/html/$(hostname -f)
   echo "<h1>It Works! Ready for Let's Encrypt.</h1>" > /var/www/html/$(hostname -f)/index.html
   ```
3. Enable required Apache modules:
   ```bash
   a2enmod ssl rewrite headers alias include negotiation socache_shmcb
   systemctl restart apache2.service
   ```
   > [!NOTE]
   > We intentionally leave `000-default.conf` enabled for now. This ensures Certbot can successfully locate a vhost to validate the ACME HTTP-01 challenge in the next step.

---

## Install and Configure Let's Encrypt (HTTPS)

> [!TIP]
> Using Let's Encrypt is the recommended, production-ready approach for obtaining trusted SSL certificates.

1. Install Certbot and the Apache plugin:
   ```bash
   sudo apt install certbot python3-certbot-apache
   ```
2. Obtain and install the certificate:
   > [!CAUTION]
   > Ensure `jagger.example.org` resolves to this server's public IP before running this command.
   ```bash
   sudo certbot --apache -d jagger.example.org
   ```
   - Follow the prompts (choose to redirect HTTP traffic to HTTPS).
3. Certbot will automatically create an SSL virtual host file at `/etc/apache2/sites-available/$(hostname -f)-le-ssl.conf`. We will configure this file with Jagger-specific rules in a later step.
4. Verify auto-renewal:
   ```bash
   sudo certbot renew --dry-run
   ```

---

## Install PyFF (Metadata Processing)

[PyFF](https://github.com/IdentityPython/pyFF) (Python Federation Feeder) is a SAML metadata aggregator, used for advanced SAML metadata filtering, signing, and publishing.

1. Install build dependencies for PyFF:
   ```bash
   sudo apt install python3-venv python3-pip libxml2-dev libxslt1-dev pkg-config
   ```
2. Create a dedicated directory and virtual environment:
   ```bash
   sudo mkdir -p /opt/pyff
   sudo chown root:root /opt/pyff
   python3 -m venv /opt/pyff/venv
   ```
3. Activate the environment and install PyFF:
   ```bash
   source /opt/pyff/venv/bin/activate
   pip install --upgrade pip
   pip install pyff
   ```
4. Create global symlinks for easy access:
   ```bash
   sudo ln -s /opt/pyff/venv/bin/pyff /usr/local/bin/pyff
   sudo ln -s /opt/pyff/venv/bin/pyffd /usr/local/bin/pyffd
   ```

---

## Install XMLSecTool (Metadata Validation)

[XMLSecTool](https://shibboleth.atlassian.net/wiki/spaces/XSTJ3) is a command-line Java utility for checking the XML signature and/or XML encryption of a SAML metadata file, and validating it against an XML Schema.

1. Create the installation directory:
   ```bash
   sudo mkdir -p /opt/xmlsectool
   cd /opt/xmlsectool
   ```
2. Download the latest stable release (4.0.0) from the official Shibboleth distribution:
   ```bash
   sudo wget https://shibboleth.net/downloads/tools/xmlsectool/4.0.0/xmlsectool-4.0.0-bin.zip
   sudo unzip xmlsectool-4.0.0-bin.zip
   sudo rm xmlsectool-4.0.0-bin.zip
   sudo chown -R root:root /opt/xmlsectool
   ```
3. Create a wrapper script for global execution:
   ```bash
   sudo nano /usr/local/bin/xmlsectool
   ```
   Add the following content:
   ```bash
   #!/bin/bash
   java -jar /opt/xmlsectool/xmlsectool-4.0.0/xmlsectool.jar "$@"
   ```
4. Make the script executable:
   ```bash
   sudo chmod +x /usr/local/bin/xmlsectool
   ```
5. Verify installation:
   ```bash
   xmlsectool --help
   ```

---

## Install Jagger

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Install required PHP and Java packages:
   > [!NOTE]
   > `php-xmlrpc` has been intentionally omitted as it was permanently removed in PHP 8.0+.
   ```bash
   apt install -y curl php php-common php-gd php-curl php-mysql php-intl php-xml php-mbstring php-soap php-bcmath php-cli php-zip php-gearman php-apcu php-memcached default-jdk gearman-job-server --no-install-recommends
   ```
3. Install Composer:
   ```bash
   curl -sS https://getcomposer.org/installer | php
   cp composer.phar /usr/local/bin/composer
   ```
4. Install CodeIgniter:
   ```bash
   cd /opt
   wget https://github.com/bcit-ci/CodeIgniter/archive/refs/tags/3.1.13.tar.gz -O /opt/codeigniter-3.1.13.tar.gz
   rm -rf /opt/codeigniter
   mkdir -p /opt/codeigniter
   tar -xzf /opt/codeigniter-3.1.13.tar.gz -C /opt/codeigniter --strip-components=1
   
   # Verify installation
   ls -la /opt/codeigniter
   grep "CI_VERSION" /opt/codeigniter/system/core/CodeIgniter.php
   ```
5. Download Jagger:
   ```bash
   git clone https://github.com/Edugate/Jagger /opt/rr3
   ```
6. Install required third-party libraries:
   - Edit `/opt/rr3/application/composer.json`:
     - Replace `"mtdowling/cron-expression": "1.1.*"` with `"dragonmantank/cron-expression": "^3.0"`
     - Update `"laminas/laminas-permissions-acl"` version to `"^2.18.0"`
   - Run composer:
     ```bash
     cd /opt/rr3/application
     sudo composer install
     ```
7. Configure the `index.php` file:
   ```bash
   cp /opt/codeigniter/index.php /opt/rr3/
   ```
   Edit `/opt/rr3/index.php` and set:
   ```php
   $system_path = '/opt/codeigniter/system';
   ```

---

## Configure Jagger Database

```bash
mysql -u root
```
```sql
CREATE DATABASE rr3 CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'rr3user'@'localhost' IDENTIFIED BY 'rr3pass';
GRANT ALL PRIVILEGES ON rr3.* TO 'rr3user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```
> [!NOTE]
> `utf8mb4` is strictly recommended over `utf8` for full Unicode/emoji support in modern MySQL/MariaDB.

---

## Configure Jagger

```bash
mkdir -p /var/log/rr3
chown -R www-data:www-data /var/log/rr3
chown -R www-data:www-data /opt/rr3/application /opt/rr3/application/models/Proxies
cd /opt/rr3
./install.sh
cd /opt/rr3/application/config
```

### 1. `config.php`
```bash
cp config-default.php config.php
```
Generate key via: 
```bash
openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
```
Edit `config.php`:
```php
$config['base_url'] = 'https://jagger.example.org/rr3';
$config['index_page'] = '';
$config['log_threshold'] = 1;
$config['log_path'] = '/var/log/rr3/';
$config['encryption_key'] = '<ENCRYPTION-KEY>'; // Paste generated key here
```

### 2. `config_rr.php`
```bash
cp config_rr-default.php config_rr.php
```
Generate syncpass key via: 
```bash
openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
```
Edit `config_rr.php`:
```php
$config['rr_setup_allowed'] = TRUE; // MUST be set to FALSE after Jagger setup
$config['site_logo'] = 'logo-default.png'; // Store file in /opt/rr3/images/
$config['syncpass'] = '<SYNCPASS>'; // Paste generated key here
$config['Shib_required'] = array('Shib_mail','Shib_username');
$config['gearman'] = TRUE;
// NOTE: Remove $config['nameids'] and all its content entirely to prevent PHP 8.x errors.
```

### 3. `database.php`
```bash
cp database-default.php database.php
```
Edit `database.php`:
```php
$db['default']['username'] = 'rr3user';
$db['default']['password'] = 'rr3pass';
$db['default']['database'] = 'rr3';
$db['default']['dsn']      = 'mysql:host=127.0.0.1;port=3306;dbname=rr3';
```

### 4. Other Configs
```bash
cp email-default.php email.php
cp memcached-default.php memcached.php
```

---

## Populate Database Tables

```bash
cd /opt/rr3/application
./doctrine
./doctrine orm:schema-tool:create
./doctrine orm:generate-proxies
```

---

## PHP Compatibility & Code Fixes

Modern PHP versions require minor adjustments to the underlying CodeIgniter 3.x framework to prevent deprecation warnings from corrupting HTTP headers.

### 1. Update CodeIgniter Exception Levels
PHP 8.4 deprecated the `E_STRICT` constant. Remove it to prevent initialization errors.
- Open `/opt/codeigniter/system/core/Exceptions.php`
- Locate the `$levels` array (around line 58) and remove `E_STRICT`:
  ```php
  public $levels = array(
      E_ERROR         => 'Error',
      E_WARNING       => 'Warning',
      E_PARSE         => 'Parsing Error',
      E_NOTICE        => 'Notice',
      E_CORE_ERROR    => 'Core Error',
      E_CORE_WARNING  => 'Core Warning',
      E_COMPILE_ERROR => 'Compile Error',
      E_COMPILE_WARNING => 'Compile Warning',
      E_USER_ERROR    => 'User Error',
      E_USER_WARNING  => 'User Warning',
      E_USER_NOTICE   => 'User Notice'
      // E_STRICT intentionally omitted for PHP 8.4+ compatibility
  );
  ```

### 2. Set Environment to Production
PHP 8.2+ deprecated dynamic properties. Setting the environment to `production` ensures non-fatal deprecation notices are logged internally rather than output to the browser.
- Open `/opt/rr3/index.php`
- Update the `ENVIRONMENT` definition (around line 50-60):
  ```php
  define('ENVIRONMENT', isset($_SERVER['CI_ENV']) ? $_SERVER['CI_ENV'] : 'production');
  ```

### 3. Disable PCRE JIT (Recommended for Secure Environments)
Strict server security policies (e.g., SELinux, AppArmor) often block JIT memory allocation, causing `preg_replace()` warnings.
- Open your active PHP configuration files (e.g., `/etc/php/8.4/apache2/php.ini` and `/etc/php/8.4/cli/php.ini`)
- Search for `pcre.jit` and set:
  ```ini
  pcre.jit=0
  ```
- Restart Apache: `systemctl restart apache2.service`

---

## Finalize Apache Jagger VirtualHost

Since Let's Encrypt generated the SSL virtual host, we must inject the Jagger-specific rules into it.

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Edit the Let's Encrypt SSL configuration file:
   ```bash
   nano /etc/apache2/sites-available/$(hostname -f)-le-ssl.conf
   ```
3. Update the file to match the following structure (ensure `jagger.example.org` is replaced):

   ```apache
   <IfModule mod_ssl.c>
   <VirtualHost *:443>
     ServerName jagger.example.org
     ServerAdmin admin@example.org
     
     CustomLog /var/log/apache2/jagger.example.org-access.log combined
     ErrorLog /var/log/apache2/jagger.example.org-error.log
     
     DocumentRoot /var/www/html/jagger.example.org
     
     # Let's Encrypt managed certificates (DO NOT MODIFY THESE 3 LINES)
     SSLCertificateFile /etc/letsencrypt/live/jagger.example.org/fullchain.pem
     SSLCertificateKeyFile /etc/letsencrypt/live/jagger.example.org/privkey.pem
     Include /etc/letsencrypt/options-ssl-apache.conf

     # Jagger Specific Security Headers
     <IfModule headers_module>
        Header set X-Frame-Options DENY
        Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
     </IfModule>

     # Jagger Application Routing
     Alias /rr3 /opt/rr3
     <Directory /opt/rr3>
        Require all granted
        RewriteEngine On
        RewriteBase /rr3
        RewriteCond $1 !^(Shibboleth\.sso|index\.php|logos|signedmetadata|flags|images|app|schemas|fonts|styles|js|robots\.txt|pub|includes)
        RewriteRule ^(.*)$ /rr3/index.php?/$1 [L]
     </Directory>
     
     # Protect application directory
     <Directory /opt/rr3/application>
        Require all denied
     </Directory>

   </VirtualHost>
   </IfModule>
   ```
4. Test configuration and restart Apache:
   ```bash
   apache2ctl configtest
   systemctl restart apache2.service
   ```
5. Verify the web application loads securely at: `https://jagger.example.org/rr3`
6. Verify your SSL configuration strength at [SSL Labs](https://www.ssllabs.com/ssltest/analyze.html).

---

## Setup Jagger Registry

1. Navigate to: `https://jagger.example.org/rr3/setup`
2. Create the initial Admin user.
3. **Crucial Security Step**: Edit `/opt/rr3/application/config/config_rr.php` and change:
   ```php
   $config['rr_setup_allowed'] = FALSE;
   ```

---

## Updating Jagger

> [!WARNING]
> **Always back up your code and database before performing an update.**

1. Pull the latest code from the Git repository:
   ```bash
   cd /opt/rr3
   git pull
   ```
2. Navigate to the application folder and update the database schema:
   ```bash
   cd /opt/rr3/application
   ./doctrine orm:schema-tool:update --force
   ./doctrine orm:generate-proxies
   ```
3. Sign in to the application and trigger the upgrade routine by visiting:
   `https://jagger.example.org/rr3/update/upgrade`
4. Always compare your local `/opt/rr3/index.php` with CodeIgniter's default `index.php` and update the local one if necessary.

---

Back to [README](README.md).
