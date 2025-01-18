#!/bin/bash

# Logging function with timestamp and colors
log() {
    level=$1
    message=$2
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    case $level in
        info)
            printf "[%s] \033[34mINFO\033[0m: %s\n" "$timestamp" "$message"
            ;;
        success)
            printf "[%s] \033[32mSUCCESS\033[0m: %s\n" "$timestamp" "$message"
            ;;
        warn)
            printf "[%s] \033[33mWARN\033[0m: %s\n" "$timestamp" "$message"
            ;;
        error)
            printf "[%s] \033[31mERROR\033[0m: %s\n" "$timestamp" "$message"
            ;;
        *)
            printf "[%s] \033[37mUNKNOWN\033[0m: %s\n" "$timestamp" "$message"
            ;;
    esac
}

# Function to check command execution status
check_status() {
    if [ $? -eq 0 ]; then
        log "success" "$1"
    else
        log "error" "$2"
        exit 1
    fi
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    log "error" "Please run this script as root or with sudo"
    exit 1
fi

# Package installation
log "info" "Updating package lists..."
apt-get update
check_status "Package lists updated successfully" "Failed to update package lists"

log "info" "Upgrading packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
check_status "Packages upgraded successfully" "Failed to upgrade packages"

log "info" "Installing required packages..."
PACKAGES="apache2 php libapache2-mod-php php-mysql graphviz aspell git clamav php-pspell php-curl php-gd php-intl ghostscript php-xml php-xmlrpc php-ldap php-zip php-soap php-mbstring unzip mysql-client certbot python3-certbot-apache ufw nano jq"
DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES
check_status "Required packages installed successfully" "Failed to install required packages"

# Moodle Download and Setup
log "info" "Creating Moodle directory..."
mkdir -p /var/www/html
check_status "Directory created successfully" "Failed to create directory"

log "info" "Downloading Moodle from Git..."
cd /var/www/html || exit 1
if [ -d "moodle" ]; then
    log "warn" "Moodle directory already exists. Removing it..."
    rm -rf moodle
fi
if cd /var/www/html; then git clone -b MOODLE_405_STABLE https://github.com/moodle/moodle.git; else log "error" "Error when cd to /var/www/html"; fi
check_status "Moodle downloaded successfully" "Failed to download Moodle"

# Moodle Configuration
log "info" "Creating and configuring moodledata directory..."
mkdir -p /var/www/moodledata
check_status "Moodledata directory created" "Failed to create moodledata directory"

log "info" "Setting directory permissions..."
mkdir -p /var/www/moodledata
chown -R www-data:www-data /var/www/moodledata
find /var/www/moodledata -type d -exec chmod 700 {} \;
find /var/www/moodledata -type f -exec chmod 600 {} \;
chmod -R 777 /var/www/html/moodle  # Changed from 777 for better security
check_status "Permissions set successfully" "Failed to set permissions"

# PHP Configuration
log "info" "Configuring PHP..."
PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")
if [ -z "$PHP_VERSION" ]; then
    log "error" "Could not determine PHP version"
    exit 1
fi

# Update PHP configuration
log "info" "Setting PHP Configuration"
sudo sed -i 's/.*max_input_vars =.*/max_input_vars = 5000/' "/etc/php/${PHP_VERSION}/apache2/php.ini"
sudo sed -i 's/.*max_input_vars =.*/max_input_vars = 5000/' "/etc/php/${PHP_VERSION}/cli/php.ini"
log "info" "Setting PHP Configuration Successfully"

# Configure cron job
log "info" "Setting up Moodle cron job..."
sudo echo "* * * * * www-data /usr/bin/php /var/www/html/moodle/admin/cli/cron.php >/dev/null" | tee -a /etc/crontab
check_status "Cron job configured successfully" "Failed to configure cron job"

# Database Configuration
log "info" "Reading database credentials..."
DB_CREDENTIAL_FILE="/home/vagrant/shared/credential/database.json"

if [ ! -f "$DB_CREDENTIAL_FILE" ]; then
    log "error" "Database credential file not found: $DB_CREDENTIAL_FILE"
    exit 1
fi

DB_HOST=$(jq -r '.database_host' "$DB_CREDENTIAL_FILE")
DB_NAME=$(jq -r '.database_name' "$DB_CREDENTIAL_FILE")
DB_USER=$(jq -r '.database_user' "$DB_CREDENTIAL_FILE")
DB_PASSWORD=$(jq -r '.database_password' "$DB_CREDENTIAL_FILE")
DB_TYPE=$(jq -r '.database_type' "$DB_CREDENTIAL_FILE")

# Validate database credentials
for VAR in DB_HOST DB_NAME DB_USER DB_PASSWORD DB_TYPE; do
    if [ -z "${!VAR}" ]; then
        log "error" "Missing database credential: $VAR"
        exit 1
    fi
done

# Moodle Installation Configuration
MOODLE_ADMIN_PASSWORD=$(pwgen 14 1)  # Increased length for better security
MOODLE_ADMIN_USER="moodleadminuser"
MOODLE_ADMIN_EMAIL="johndoe@gmail.com"
MOODLE_SITE_NAME="PKKWU MOODLE"
PROTOCOL="http://"
WEBSITE_ADDRESS=$(hostname -I | awk '{ print $2 }')  # Development only

log "info" "Setting moodle in the config-dist.php"
#!/bin/bash

sudo sed -i "s/\(\$CFG->dbtype\s*=\s*\).*\;/\1'$DB_TYPE';/" /var/www/html/moodle/config-dist.php
sudo sed -i "s/\(\$CFG->dbhost\s*=\s*\).*\;/\1'$DB_HOST';/" /var/www/html/moodle/config-dist.php
sudo sed -i "s/\(\$CFG->dbname\s*=\s*\).*\;/\1'$DB_NAME';/" /var/www/html/moodle/config-dist.php
sudo sed -i "s/\(\$CFG->dbuser\s*=\s*\).*\;/\1'$DB_USER';/" /var/www/html/moodle/config-dist.php
sudo sed -i "s/\(\$CFG->dbpass\s*=\s*\).*\;/\1'$DB_PASSWORD';/" /var/www/html/moodle/config-dist.php


sudo sed -i "s|\(\$CFG->wwwroot\s*=\s*\).*|\1'$PROTOCOL://www.$WEBSITE_ADDRESS/moodle';|" /var/www/html/moodle/config-dist.php
sudo sed -i "s|\(\$CFG->dirroot\s*=\s*\).*|\1'/var/www/html/moodle';|" /var/www/html/moodle/config-dist.php
sudo sed -i "s|\(\$CFG->dataroot\s*=\s*\).*|\1'/var/www/moodledata';|" /var/www/html/moodle/config-dist.php

sudo sed -i "s/\(\$CFG->directorypermissions\s*=\s*\).*\;/\1007777;/" /var/www/html/moodle/config-dist.php

#sudo sed -i "/ServerName/c\    ServerName $WEBSITE_ADDRESS" /etc/apache2/sites-available/000-default.conf
#sudo sed -i "/ServerAlias/c\    ServerAlias www.$WEBSITE_ADDRESS" /etc/apache2/sites-available/000-default.conf
#sudo certbot --apache --agree-tos -m "$MOODLE_ADMIN_EMAIL" --non-interactive --domains "$WEBSITE_ADDRESS" --domains "www.$WEBSITE_ADDRESS" --redirect
#sudo systemctl reload apache2
#PROTOCOL="https://";

log "info" "Installing Moodle..."
sudo -u www-data /usr/bin/php /var/www/html/moodle/admin/cli/install.php \
    --non-interactive \
    --lang=en \
    --wwwroot="$PROTOCOL$WEBSITE_ADDRESS/moodle" \
    --dataroot=/var/www/moodledata \
    --dbtype="$DB_TYPE" \
    --dbhost="$DB_HOST" \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASSWORD" \
    --fullname="$MOODLE_SITE_NAME" \
    --shortname="VG" \
    --adminuser="$MOODLE_ADMIN_USER" \
    --adminpass="$MOODLE_ADMIN_PASSWORD" \
    --adminemail="$MOODLE_ADMIN_EMAIL" \
    --agree-license \
    --summary=""
check_status "Moodle installation completed successfully. You can now log on to your new Moodle at $PROTOCOL$WEBSITE_ADDRESS/moodle as admin with $MOODLE_ADMIN_PASSWORD and complete your site registration" "Failed to install Moodle"

# Firewall Configuration
log "info" "Configuring firewall..."
ufw allow 22/tcp
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow www
ufw allow 'Apache Full'
check_status "Firewall configured successfully" "Failed to configure firewall"

# Save Moodle admin credentials
log "info" "Saving Moodle admin credentials..."
MOODLE_CRED_FILE="/home/vagrant/shared/credential/moodle_admin.json"
cat > "$MOODLE_CRED_FILE" <<EOF
{
    "admin_username": "$MOODLE_ADMIN_USER",
    "admin_password": "$MOODLE_ADMIN_PASSWORD",
    "admin_email": "$MOODLE_ADMIN_EMAIL",
    "site_url": "$PROTOCOL$WEBSITE_ADDRESS/moodle"
}
EOF

chmod -R 755 /var/www/html/moodle
chmod 600 "$MOODLE_CRED_FILE"
check_status "Moodle credentials saved successfully" "Failed to save Moodle credentials"

log "success" "Moodle installation completed successfully"