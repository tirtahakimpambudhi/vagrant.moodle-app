#!/bin/bash

# Logging function
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

# Configuration variables
MYSQL_ROOT_PASSWORD=$(pwgen 14 1)
MOODLE_DB="moodle"
MOODLE_USER="moodleuser"
MOODLE_PASSWORD=$(pwgen 14 1)
DATABASE_IP=$(hostname -I | awk '{ print $2 }')

# Check if MySQL is running
if ! systemctl is-active --quiet mysql; then
    log "error" "MySQL service is not running"
    exit 1
fi

log "info" "Configuring MySQL for remote access"

# Backup existing configuration
log "info" "Backing up MySQL configuration"
sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup

# Update bind-address in MySQL configuration
log "info" "Updating bind-address in MySQL configuration"
log "info" "Updating MySQL configuration"
# Update bind-address and add InnoDB settings
sudo sed -i 's/^bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

log "info" "Restarting MySQL service"
sudo systemctl restart mysql

wait 10s

# Setting root password
log "info" "Setting MySQL root password."
# For fresh installation (when root has no password)
sudo mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}" 2>/dev/null || \
# For existing installation (when root already has a password)
sudo mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null

if [ $? -eq 0 ]; then
    log "success" "Root password set successfully."
else
    log "error" "Failed to set root password. Please check if MySQL is running and accessible."
    exit 1
fi

# Use root password for subsequent commands
MYSQL_CMD="sudo mysql -u root -p${MYSQL_ROOT_PASSWORD}"

# Removing anonymous users
log "info" "Removing anonymous users."
$MYSQL_CMD -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
if [ $? -eq 0 ]; then
    log "success" "Anonymous users removed successfully."
else
    log "error" "Failed to remove anonymous users."
    exit 1
fi

# Removing demo database
log "info" "Removing demo database."
$MYSQL_CMD -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
if [ $? -eq 0 ]; then
    log "success" "Demo database removed successfully."
else
    log "error" "Failed to remove demo database."
    exit 1
fi

# Flushing privileges
log "info" "Flushing privileges."
$MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
if [ $? -eq 0 ]; then
    log "success" "Privileges flushed successfully."
else
    log "error" "Failed to flush privileges."
    exit 1
fi

# Setting global variable
log "info" "Setting global variable net_read_timeout."
$MYSQL_CMD -e "SET GLOBAL net_read_timeout = 45;" 2>/dev/null
if [ $? -eq 0 ]; then
    log "success" "Global variable net_read_timeout set successfully."
else
    log "error" "Failed to set global variable net_read_timeout."
    exit 1
fi

# Creating Moodle database and user
log "info" "Creating database and user for Moodle."
$MYSQL_CMD <<MYSQL_SCRIPT
# Create database
CREATE DATABASE IF NOT EXISTS ${MOODLE_DB} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

# Drop user if exists to avoid conflicts
DROP USER IF EXISTS '${MOODLE_USER}'@'localhost';
DROP USER IF EXISTS '${MOODLE_USER}'@'%';

# Create user with proper privileges
CREATE USER '${MOODLE_USER}'@'localhost' IDENTIFIED BY '${MOODLE_PASSWORD}';
CREATE USER '${MOODLE_USER}'@'%' IDENTIFIED BY '${MOODLE_PASSWORD}';

# Grant privileges
GRANT ALL PRIVILEGES ON ${MOODLE_DB}.* TO '${MOODLE_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${MOODLE_DB}.* TO '${MOODLE_USER}'@'%';

# Apply changes
FLUSH PRIVILEGES;
MYSQL_SCRIPT

if [ $? -eq 0 ]; then
    log "success" "Moodle database and user created successfully."
else
    log "error" "Failed to create Moodle database and user."
    exit 1
fi

# Verify user creation and privileges
log "info" "Verifying user privileges"
$MYSQL_CMD -e "SHOW GRANTS FOR '${MOODLE_USER}'@'localhost';" 2>/dev/null
if [ $? -eq 0 ]; then
    log "success" "User privileges verified successfully."
else
    log "error" "Failed to verify user privileges."
    exit 1
fi
# Ensure directory exists
mkdir -p "/home/vagrant/shared/credential"

# Remove the old credential if it exists
if [ -f "/home/vagrant/shared/credential/database.json" ]; then
    log "info" "File shared/credential/database.json exists. Removing it..."
    rm -f "/home/vagrant/shared/credential/database.json"
fi

log "info" "Writing credentials to database.json"
# Create a JSON file with credentials database server
cat <<EOF > "/home/vagrant/shared/credential/database.json"
{
    "database_host": "$DATABASE_IP",
    "database_root_password": "$MYSQL_ROOT_PASSWORD",
    "database_name": "$MOODLE_DB",
    "database_user": "$MOODLE_USER",
    "database_password": "$MOODLE_PASSWORD",
    "database_type": "mysqli"
}
EOF

chmod 600 "/home/vagrant/shared/credential/database.json"
# Configure firewall
log "info" "Configuring firewall for MySQL"
sudo ufw enable
sudo ufw allow 3306/tcp
sudo ufw reload