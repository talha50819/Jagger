Jagger
===

Jagger (http://jagger.heanet.ie) is developed by HEAnet to manage the Edugate multiparty SAML federation. Other organisations use Jagger to manage their federations but it can be used to manage the web-of-trust for a single entity. It can also be used a a GUI for the Shibboleth SAML Identity Provider (www.shibboleth.net)

Features: 

1. Synchronise SAML metadata from another federation.
2. Create and manage a federation
3. Create a single circle of trust containing metadata of all entities that your organisation particpates via multiple federations.
4. GUI to manage to the attribute policy of identity providers based on the Shibboleth SAML implementation.
5. Filter the RequestedAttribute's of a SAML service provider to allow and IdP release attributes to such providers based on a policy set in the Jagger GUI.
6. Create and edit metadata of individual entities.
7. Notification subsystem with subscription options

----

# HOWTO Install and Configure Jagger Federation Registry on Debian based Linux Distribution

## Table of Contents

1.  [Requirements](#requirements)
    1.  [Hardware](#hardware)
    2.  [Software](#software)
    3.  [Others](#others)
2.  [Notes](#notes)
3.  [Configure the environment](#configure-the-environment)
4.  [Configure APT Mirror](#configure-apt-mirror)
5.  [Install Dependencies](#install-dependencies)
6.  [Install MySQL Server](#install-mysql-server)
    1. [Protect MySQL Server](#protect-mysql-server)
7.  [Install Apache Web Server](#install-apache-web-server)
8.  [Configure Apache Web Server](#configure-apache-web-server)
9.  [Install Jagger](#install-jagger)
10. [Configure Jagger database](#configure-jagger-database)
11. [Configure Jagger](#configure-jagger)
12. [Populate database tables](#populate-database-tables)
13. [Code fixes](#code-fixes)
14. [Configure Apache Jagger VirtualHost](#configure-apache-jagger-virtualhost)
15. [Setup Jagger Registry](#setup-jagger-registry)
16. [Documentation](#documentation)
17. [Authors](#authors)
18. [Thanks](#thanks)

## Requirements

### Hardware

-   CPU: 4 Core (64 bit)
-   RAM: 8 GB
-   HDD: 50 GB
-   OS:
    - Debian 13.*
    - Ubuntu 26.*

### Software

-   Apache Web Server (*2.4*)
-   OpenSSL (*3.5*)
-   Shibboleth Service Provider (*5*) - Optionally
-   PHP (*8.5*)

### Others

-   SSL Credentials: HTTPS Certificate & Private Key
-   Logo:
    -   size: 64px by 350px wide and 64px by 146px high
    -   format: PNG
    -   style: with a transparent background

[TOC](#table-of-contents)

## Notes

This HOWTO uses `example.org` and `jagger.example.org` as example values.

Please remember to **replace all occurencences** of:

-   the `example.org` value with the domain name
-   the `jagger.example.org` value with the Full Qualified Domain Name of the Jagger instance.

[TOC](#table-of-contents)

## Configure the environment

1.  Become ROOT:

    ``` text
    sudo su -
    ```

2.  Be sure that your firewall **is not blocking** the traffic on port **443** and **80** for the Jagger server.

3.  Set the SP hostname:

    **!!!ATTENTION!!!**: Replace `jagger.example.org` with your SP Full Qualified Domain Name and `<HOSTNAME>` with the Jagger hostname

    -   ``` text
        echo "<YOUR-SERVER-IP-ADDRESS> jagger.example.org <HOSTNAME>" >> /etc/hosts
        ```

    -   ``` text
        hostnamectl set-hostname <HOSTNAME>

[TOC](#table-of-contents)

## Configure APT Mirror

Debian Mirror List: <https://www.debian.org/mirror/list>

Ubuntu Mirror List: <https://launchpad.net/ubuntu/+archivemirrors>

Example with the Consortium GARR italian mirrors:

1.  Become ROOT:

    ``` text
    sudo su -
    ```

2.  Change the default mirror:

    -   Debian - Deb822 file format:

        ``` text
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

    -   Ubuntu:

        ``` text
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

3.  Update packages:

    ``` text
    apt update && apt-get upgrade -y --no-install-recommends
    ```

[TOC](#table-of-contents)

## Install Dependencies

``` text
sudo apt install fail2ban vim wget ca-certificates openssl ntpsec git --no-install-recommends
```

[TOC](#table-of-contents)

## Install MySQL Server

``` text
sudo apt install default-mysql-server --no-install-recommends
```
[TOC](#table-of-contents)

### Protect MySQL Server

``` text
sudo mysql_secure_installation
```
   
On Ubuntu:
  - Would you like to setup VALIDATE PASSWORD component? **No**
  - Remove anonymous users? **Yes**
  - Disallow root login remotely? **Yes**
  - Remove test database and access to it? **Yes**
  - Reload privilege tables now? **Yes**

On Debian:
  - Root password: **empty or a desired value for the root password of MariaDB**
  - Switch to unix_socket: **Y**
  - Change the root password? **N**
  - Remove anonymous users? **Y**
  - Disallow root login remotely? **Y**
  - Remove test database and access to it? **Y**
  - Reload privilege tables now? **Y**

[TOC](#table-of-contents)

## Install Apache Web Server

The Apache HTTP Server will be configured for SSL offloading.

``` text
sudo apt install apache2
```

[TOC](#table-of-contents)

## Configure Apache Web Server

1.  Become ROOT:

    ``` text
    sudo su -
    ```

2.  Create the DocumentRoot:

    -   ``` text
        mkdir /var/www/html/$(hostname -f)
        ```

    -   ``` text
        chown -R www-data: /var/www/html/$(hostname -f)
        ```

    -   ``` text
        echo '<h1>It Works!</h1>' > /var/www/html/$(hostname -f)/index.html
        ```

3. Generate SSL credentials:

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
    
    This automatically generates a **self-signed RSA 3072-bit SSL certificate**, private key, and CA certificate using the server's FQDN.


4.  Configure the right privileges for the SSL Certificate and Private Key used by HTTPS:

    -   ``` text
        chmod 400 /etc/ssl/private/$(hostname -f).key
        ```

    -   ``` text
        chmod 644 /etc/ssl/certs/$(hostname -f).crt
        ```

    (`$(hostname -f)` will provide your SP Full Qualified Domain Name)

5.  Verify that SSL certificate file matches the CA certificate file with:

    - ``` text
      openssl verify --CAfile /etc/ssl/certs/ca-cert.pem /etc/ssl/certs/$(hostname -f).crt
      ```

    and make sure you get an `OK` as an outcome.

6.  Enable the required Apache modules and the virtual hosts:

    -   ``` text
        a2enmod ssl rewrite headers alias include negotiation
        ```

    -   ``` text
        a2dissite 000-default.conf default-ssl
        ```

    -   ``` text
        systemctl restart apache2.service
        ```

[TOC](#table-of-contents)

## Install Jagger

1.  Become ROOT:

    ``` text
    sudo su -
    ```

2. Install packages required:

   - Ubuntu

     - ```txt
       apt install -y curl php php-common php-gd php-curl php-mysql php-intl php-xml php-mbstring php-xmlrpc php-soap php-bcmath php-cli php-zip php-gearman php-apcu php-memcached python3-pip default-jdk gearman-job-server --no-install-recommends
       ```

   - Debian:

     - ```txt
       apt install -y curl php php-common php-gd php-curl php-mysql php-intl php-xml php-mbstring php-xmlrpc php-soap php-bcmath php-cli php-zip php-gearman php-apcu php-memcached python3-pip default-jdk gearman-job-server --no-install-recommends
       ```

3. Install Composer:

   - ```txt
     curl -sS https://getcomposer.org/installer | php
     ```

   - ```txt
     cp composer.phar /usr/local/bin/composer
     ```

Absolutely. Since `/opt/codeigniter` is already correctly extracted, here is the **clean, correct sequence** from the beginning.

4. CodeIgniter installation

    ```bash
    cd /opt
    ```
    
    ```bash
    wget https://github.com/bcit-ci/CodeIgniter/archive/refs/tags/3.1.13.tar.gz -O /opt/codeigniter-3.1.13.tar.gz
    ```
    
    ```bash
    rm -rf /opt/codeigniter
    ```
    
    ```bash
    mkdir -p /opt/codeigniter
    ```
    
    ```bash
    tar -xzf /opt/codeigniter-3.1.13.tar.gz -C /opt/codeigniter --strip-components=1
    ```
    
    Verify
    
    ```bash
    ls -la /opt/codeigniter
    ```
    
    ```bash
    grep "CI_VERSION" /opt/codeigniter/system/core/CodeIgniter.php
    ```


5. Download Jagger:

   - ```txt
     git clone https://github.com/Edugate/Jagger /opt/rr3
     ```
     
6. Install required third parties libraries:

   - ```txt
     vim /opt/rr3/application/composer.json
     ```
     and replace `"mtdowling/cron-expression": "1.1.*",` with `"dragonmantank/cron-expression": "3.*",`
      
   - ```txt
     cd /opt/rr3/application ; sudo composer install
     ```

7. Configure the "index.php" file:

   - ```text
     cp /opt/codeigniter/index.php /opt/rr3/
     ```

     by setting `$system_path = '/opt/codeigniter/system'`.

[TOC](#table-of-contents)

## Configure Jagger database

```text
mysql -u root
```

- ```text
  CREATE DATABASE rr3 CHARACTER SET utf8 COLLATE utf8_general_ci;
  ```
- ```text
  CREATE USER 'rr3user'@'localhost' IDENTIFIED BY 'rr3pass';
  ```
- ```text
  GRANT ALL PRIVILEGES ON rr3.* TO rr3user@'localhost';
  ```
- ```text
  FLUSH PRIVILEGES;
  ```

[TOC](#table-of-contents)

## Configure Jagger

- ```text
  mkdir /var/log/rr3
  ```
  
- ```text
  chown www-data /var/log/rr3
  ```

- ```text
  chown www-data:www-data /opt/rr3/application /opt/rr3/application/models/Proxies
  ```
  
- ```text
  cd /opt/rr3
  ```

- ```text
  ./install.sh
  ```

- ```text
  cd /opt/rr3/application/config
  ```
  
- ```text
  cp config-default.php config.php
  ```

  `config.php` base configuration:

  - `$config['base_url'] = 'https://jagger.example.org/rr3';`
  - `$config['index_page'] = '';`
  - `$config['log_threshold'] = 1;`
  - `$config['log_path'] = '/var/log/rr3/';`
  - `$config['encryption_key'] = '<ENCRYPTION-KEY>';`

     `<ENCRYPTION-KEY>` generation:
    
     ```text
     openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
     ```

- ```text
  cp config_rr-default.php config_rr.php
  ```

  `config_rr.php` base configuration:

  - `$config['rr_setup_allowed'] = TRUE`  (HAS TO COME BACK to FALSE after Jagger setup)
  - `$config['site_logo'] = 'logo-default.png';`  (set filename to be used as main logo in top-left corner. File should be stored in `/opt/rr3/images/` folder.)
  - `$config['syncpass'] = <SYNCPASS>`
  
    `<SYNCPASS>` generation:
    
    ```text
    openssl rand -base64 128 | tr -dc 'A-Za-z0-9' | head -c 64; echo
    ```
      
  - `$config['Shib_required'] = array('Shib_mail','Shib_username');`
  - `$config['nameids'] and all its content has to be removed.`
  - `$config['gearman'] = TRUE;`
  
- ```text
  cp database-default.php database.php
  ```

  `database.php` base Configuration:
  
  - `$db['default']['username'] = 'rr3user';`
  - `$db['default']['password'] = 'rr3pass';`
  - `$db['default']['database'] = 'rr3';`
  - `$db['default']['dsn']      = 'mysql:host=127.0.0.1;port=3306;dbname=rr3';`
  
- ```text
  cp email-default.php email.php
  ```
  
- ```text
  cp memcached-default.php memcached.php
  ```

[TOC](#table-of-contents)

## Populate database tables

- ```text
  cd /opt/rr3/application
  ```

- ```text
  ./doctrine
  ```

- ```text
  ./doctrine orm:schema-tool:create
  ```

- ```text
  ./doctrine orm:generate-proxies
  ```

[TOC](#table-of-contents)

# Code fixes

Take a look to my Pull Request on: https://github.com/Edugate/Jagger/pulls

[TOC](#table-of-contents)

## Configure Apache Jagger VirtualHost

1.  Become ROOT:

    ``` text
    sudo su -
    ```

2.  Create the Virtualhost file (**PLEASE PAY ATTENTION! you need to edit this file and customize it, check the initial comment of the file**):

    ``` text
    vim /etc/apache2/sites-available/$(hostname -f).conf
    ```

    ``` text
    # This is an example Apache2 configuration for Jagger Federation Registry tool.
    #
    # Edit this file and:
    # - Adjust "jagger.example.org" with your Jagger Full Qualified Domain Name
    # - Adjust "ServerAdmin" email address
    # - Adjust "CustomLog" and "ErrorLog" with Apache log files path
    # - Adjust "SSLCertificateFile", "SSLCertificateKeyFile" and "SSLCACertificateFile" with the correct file path


    # SSL general security improvements should be moved in global settings
    # OCSP Stapling, only in httpd/apache >= 2.3.3
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
         
         # This will disallow embedding your sp's login page within an iframe.
         <IfModule headers_module>
            Header set X-Frame-Options DENY
            # Enable HTTP Strict Transport Security with a 2 year duration
            Header always set Strict-Transport-Security "max-age=63072000;includeSubDomains;preload"
         </IfModule>
         
         SSLCertificateFile /etc/ssl/certs/jagger.example.org.crt
         SSLCertificateKeyFile /etc/ssl/private/jagger.example.org.key
         SSLCACertificateFile /etc/ssl/certs/ca-cert.pem

         Alias /rr3 /opt/rr3
         <Directory /opt/rr3>
            Require all granted

            RewriteEngine On
            RewriteBase /rr3
            RewriteCond $1 !^(Shibboleth\.sso|index\.php|logos|signedmetadata|flags|images|app|schemas|fonts|styles|images|js|robots\.txt|pub|includes)
            RewriteRule  ^(.*)$ /rr3/index.php?/$1 [L]
         </Directory>
         <Directory /opt/rr3/application>
            Order allow,deny
            Deny from all
         </Directory>

       </VirtualHost>
    </IfModule>
    ```

4. Enable the Apache2 SP Virtualhosts created:

    -   ``` text
        a2ensite $(hostname -f).conf
        ```

    -   ``` text
        systemctl restart apache2.service
        ```

5.  Check that Jagger web application works on:

    ``` text
    https://jagger.example.org
    ```

6.  Verify the strength of your SP's machine on [SSLLabs](https://www.ssllabs.com/ssltest/analyze.html).

[TOC](#table-of-contents)

## Setup Jagger Registry

Go to https://jagger.example.org/rr3/setup and create the Admin user.

After that, set to FALSE the line:

`$config['rr_setup_allowed'] = TRUE`

on `/opt/rr3/application/config/config_rr.php`

[TOC](#table-of-contents)

## Documentation

https://jagger.heanet.ie/jaggerdocadmin/index.html

[TOC](#table-of-contents)

## Authors

### Original Author

 * Muhammad Talha Siddiqui

[TOC](#table-of-contents)

## Thanks

https://github.com/janul

Before update code please make always backup of code and db

After update code from GIT repository:

 go to application folder
 run:  
 ./doctrine orm:schema-tool:update --force
 ./doctrine orm:generate-proxies 
 
 Then sign in and open http://yousite/update/upgrade

 Always compare local index.php with codeigniter's index.php and update local one if needed.
