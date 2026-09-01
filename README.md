# Jagger Federation Registry

[Jagger](http://jagger.heanet.ie) is developed by HEAnet to manage the Edugate multiparty SAML federation. Other organisations use Jagger to manage their federations, but it can also be used to manage the web-of-trust for a single entity. Additionally, it can be used as a GUI for the Shibboleth SAML Identity Provider ([Shibboleth](https://www.shibboleth.net)).

## Features

1. Synchronise SAML metadata from another federation.
2. Create and manage a federation.
3. Create a single circle of trust containing metadata of all entities that your organisation participates in via multiple federations.
4. GUI to manage the attribute policy of identity providers based on the Shibboleth SAML implementation.
5. Filter the `RequestedAttribute`s of a SAML service provider to allow an IdP to release attributes to such providers based on a policy set in the Jagger GUI.
6. Create and edit metadata of individual entities.
7. Notification subsystem with subscription options.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Important Notes](#important-notes)
3. [Configure the Environment](#configure-the-environment)
4. [Configure APT Mirror](#configure-apt-mirror)
5. [Install Dependencies](#install-dependencies)
6. [Install MySQL Server](#install-mysql-server)
7. [Install Apache Web Server](#install-apache-web-server)
8. [Configure Apache Web Server](#configure-apache-web-server)
9. [Install Jagger](#install-jagger)
10. [Configure Jagger Database](#configure-jagger-database)
11. [Configure Jagger](#configure-jagger)
12. [Populate Database Tables](#populate-database-tables)
13. [Code Fixes & PHP Compatibility](#code-fixes--php-compatibility)
14. [Configure Apache Jagger VirtualHost](#configure-apache-jagger-virtualhost)
15. [Setup Jagger Registry](#setup-jagger-registry)
16. [Updating Jagger](#updating-jagger)
17. [Documentation](#documentation)
18. [Authors & Thanks](#authors--thanks)

---

## Requirements

### Hardware
- *CPU*: 4 Core (64-bit)
- *RAM*: 8 GB
- *HDD*: 50 GB
- *OS*: Debian 13.* or Ubuntu 26.*

### Software
- *Apache Web Server*: 2.4
- *OpenSSL*: 3.5
- *Shibboleth Service Provider*: 5 *(Optional)*
- *PHP*: 8.5

### Others
- *SSL Credentials*: HTTPS Certificate & Private Key
- *Logo*: 
  - Size: 350px wide × 64px high (or 146px wide × 64px high)
  - Format: PNG
  - Style: Transparent background

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
3. Set the SP hostname:
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
   
   Types: deb deb-src
   URIs: https://ubuntu.mirror.garr.it/ubuntu/
   Suites: $VERSION_CODENAME-security
   Components: main restricted universe multiverse
   EOF'
   ```

3. Update packages:
   ```bash
   apt update && apt-get upgrade -y --no-install-recommends
   ```

---

## Install Dependencies

```bash
sudo apt install fail2ban nano wget ca-certificates openssl ntpsec git --no-install-recommends
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

The Apache HTTP Server will be configured for SSL offloading.

```bash
sudo apt install apache2
```

---

## Configure Apache Web Server

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Create the DocumentRoot:
   ```bash
   mkdir -p /var/www/html/$(hostname -f)
   chown -R www-data:www-data /var/www/html/$(hostname -f)
   echo '<h1>It Works!</h1>' > /var/www/html/$(hostname -f)/index.html
   ```
3. Generate SSL credentials (Self-signed RSA 3072-bit):
   ```bash
   mkdir -p /etc/ssl/private /etc/ssl/certs
   
   openssl req -new -x509 -newkey rsa:3072 -sha256 -days 365 \
     -noenc \
     -keyout /etc/ssl/private/$(hostname -f).key \
     -out /etc/ssl/certs/$(hostname -f).crt \
     -subj "/CN=$(hostname -f)" \
     -addext "subjectAltName=DNS:$(hostname -f)"
   
   cp /etc/ssl/certs/$(hostname -f).crt /etc/ssl/certs/ca-cert.pem
   chmod 400 /etc/ssl/private/$(hostname -f).key
   chmod 644 /etc/ssl/certs/$(hostname -f).crt
   ```
4. Verify that the SSL certificate file matches the CA certificate file:
   ```bash
   openssl verify --CAfile /etc/ssl/certs/ca-cert.pem /etc/ssl/certs/$(hostname -f).crt
   ```
   *(Ensure the output is `OK`)*
5. Enable required Apache modules and disable default sites:
   ```bash
   a2enmod ssl rewrite headers alias include negotiation
   a2dissite 000-default.conf default-ssl
   systemctl restart apache2.service
   ```

---

## Install Jagger

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Install required packages:
   ```bash
   apt install -y curl php php-common php-gd php-curl php-mysql php-intl php-xml php-mbstring php-xmlrpc php-soap php-bcmath php-cli php-zip php-gearman php-apcu php-memcached python3-pip default-jdk gearman-job-server --no-install-recommends
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
     - Replace `"mtdowling/cron-expression": "1.1.*"` with `"dragonmantank/cron-expression": "3.*"`
     - Update `"laminas/laminas-permissions-acl"` version to `"2.18.0"`
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
CREATE DATABASE rr3 CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER 'rr3user'@'localhost' IDENTIFIED BY 'rr3pass';
GRANT ALL PRIVILEGES ON rr3.* TO 'rr3user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

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
```
openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
```
Edit `config.php`:
```php
$config['base_url'] = 'https://jagger.example.org/rr3';
$config['index_page'] = '';
$config['log_threshold'] = 1;
$config['log_path'] = '/var/log/rr3/';
$config['encryption_key'] = '<ENCRYPTION-KEY>'; //Generated key
```

### 2. `config_rr.php`
```bash
cp config_rr-default.php config_rr.php
```
Generate key via: 
```
openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
```
Edit `config_rr.php`:
```php
$config['rr_setup_allowed'] = TRUE; // MUST be set to FALSE after Jagger setup
$config['site_logo'] = 'logo-default.png'; // Store file in /opt/rr3/images/
$config['syncpass'] = '<SYNCPASS>'; //Generated key
$config['Shib_required'] = array('Shib_mail','Shib_username');
$config['gearman'] = TRUE;
// NOTE: Remove $config['nameids'] and all its content entirely.
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

## PHP Compatibility

Modern PHP versions require minor adjustments to the underlying CodeIgniter 3.x framework and specific directory permissions to ensure a smooth deployment. This prevents deprecation warnings from corrupting HTTP headers.

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
PHP 8.2+ deprecated dynamic properties. Setting the environment to `production` ensures non-fatal deprecation notices are logged internally rather than output to the browser (preventing "Headers already sent" errors).
- Open `/opt/rr3/index.php`
- Update the `ENVIRONMENT` definition (around line 50-60):
  ```php
  define('ENVIRONMENT', isset($_SERVER['CI_ENV']) ? $_SERVER['CI_ENV'] : 'production');
  ```

### 3. Disable PCRE JIT (Recommended for Secure Environments)
Strict server security policies (e.g., SELinux, AppArmor) often block JIT memory allocation, causing `preg_replace()` warnings.
- Open your active PHP configuration files (e.g., `/etc/php/8.5/apache2/php.ini` and `/etc/php/8.5/cli/php.ini`)
- Search for `pcre.jit` and set:
  ```ini
  pcre.jit=0
  ```

---

## Configure Apache Jagger VirtualHost

1. Become `root`:
   ```bash
   sudo su -
   ```
2. Create the VirtualHost file:
   ```bash
   nano /etc/apache2/sites-available/$(hostname -f).conf
   ```
3. Paste the following configuration (remember to replace `jagger.example.org` and email paths):

   ```apache
   # Jagger Federation Registry Apache2 Configuration
   # Adjust "jagger.example.org", "ServerAdmin", log paths, and SSL file paths as needed.

   SSLUseStapling on
   SSLStaplingResponderTimeout 5
   SSLStaplingReturnResponderErrors off
   SSLStaplingCache shmcb:/var/run/ocsp(128000)

   <VirtualHost *:80>
      ServerName "jagger.example.org"
      RedirectMatch permanent ^/$ /rr3
   </VirtualHost>

   <IfModule mod_ssl.c>
      <VirtualHost _default_:443>
        ServerName jagger.example.org:443
        ServerAdmin admin@example.org
        RedirectMatch permanent ^/$ /rr3

        CustomLog /var/log/apache2/jagger.example.org.log combined
        ErrorLog /var/log/apache2/jagger.example.org-error.log
        
        DocumentRoot /var/www/html/jagger.example.org
        
        SSLEngine On
        SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
        SSLCipherSuite "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS !RC4"
        SSLHonorCipherOrder on
        
        <IfModule headers_module>
           Header set X-Frame-Options DENY
           Header always set Strict-Transport-Security "max-age=63072000;includeSubDomains;preload"
        </IfModule>
        
        SSLCertificateFile /etc/ssl/certs/$(hostname -f).crt
        SSLCertificateKeyFile /etc/ssl/private/$(hostname -f).key
        SSLCACertificateFile /etc/ssl/certs/ca-cert.pem

        Alias /rr3 /opt/rr3
        <Directory /opt/rr3>
           Require all granted
           RewriteEngine On
           RewriteBase /rr3
           RewriteCond $1 !^(Shibboleth\.sso|index\.php|logos|signedmetadata|flags|images|app|schemas|fonts|styles|js|robots\.txt|pub|includes)
           RewriteRule ^(.*)$ /rr3/index.php?/$1 [L]
        </Directory>
        
        <Directory /opt/rr3/application>
           Require all denied
        </Directory>
      </VirtualHost>
   </IfModule>
   ```
4. Enable the site and restart Apache:
   ```bash
   a2ensite $(hostname -f).conf
   apache2ctl configtest
   systemctl restart apache2.service
   ```
5. Verify the web application loads at: `https://jagger.example.org`
6. Verify your SSL configuration strength at [SSL Labs](https://www.ssllabs.com/ssltest/analyze.html).

---

## Setup Jagger Registry

1. Navigate to: `https://jagger.example.org/rr3/setup`
2. Create the Admin user.
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
   `http://yoursite/update/upgrade`
4. Always compare your local `/opt/rr3/index.php` with CodeIgniter's default `index.php` and update the local one if necessary.

---

## Documentation

Official administration documentation is available at:  
[https://jagger.heanet.ie/jaggerdocadmin/index.html](https://jagger.heanet.ie/jaggerdocadmin/index.html)

---

## Authors & Thanks

- **Fork Author**: Muhammad Talha Siddiqui
- **Project Repository**: [Edugate/Jagger](https://github.com/Edugate/Jagger)
