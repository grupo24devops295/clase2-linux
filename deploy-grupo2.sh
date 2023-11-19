#!/bin/bash
#set -e

# MySQL root credentials
DB_ROOT_USER="root"

# Database and user details variables.
DB_NAME="devopstravel"
DB_USER="codeuser"

# Script directory
SCRIPT_DIR=$(pwd)

echo "Checking if this script is run by root"
#check if script is being run as root.
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Updating packages index"
# Update the package list.
apt update -qq

# Function to display progress bar.
function progress_bar() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local bar_length=30

    # Calculate the number of completed bars and spaces
    local completed_bar=$((percent * bar_length / 100))
    local spaces=$((bar_length - completed_bar))

    # Construct the progress bar representation
    local bar="["
    for ((i = 1; i <= completed_bar; i++)); do
        bar+="#"
    done
    for ((i = 1; i <= spaces; i++)); do
        bar+=" "
    done
    bar+="]"

    printf "\r%s %d%%" "$bar" "$percent"
}

# Install Apache, MariaDB, PHP, Curl, Git packages.
packages=("apache2" "mariadb-server" "php" "libapache2-mod-php" "php-mysql" "php-mbstring" "php-zip" "php-gd" "php-json" "php-curl" "curl" "git")
total_count=${#packages[@]}
package_count=0

for package in "${packages[@]}"; do
    # Check if package is already installed.
    if dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -q "installed"; then
        package_count=$((package_count + 1))
        progress_bar "$package_count" "$total_count"
        echo "$package already installed."
    else
        # Install package and show output
        if apt-get install -y "$package"; then
            package_count=$((package_count + 1))
            progress_bar "$package_count" "$total_count"
            echo "$package installed successfully."
        else
            echo "Failed to install $package."
        fi
    fi
done

# Start and enable all services if installation was successful.
if [ $package_count -eq $total_count ]; then
    systemctl start apache2 --quiet
    systemctl enable apache2 --quiet
    systemctl start mariadb --quiet
    systemctl enable mariadb --quiet
    echo "Services started and enabled successfully."
fi

# Repo variables
REPO_URL="https://github.com/vramirez0113/bootcamp-devops-2023.git"
REPO_NAME="bootcamp-devops-2023"
BRANCH="clase2-linux-bash"

# Config Git account
git config --global user.name "vramirez0113"
git config --global user.email "vlakstarit@gmail.com"

# Check if app REPO_URL exist before cloning
if [ -d "$REPO_NAME" ]; then
    echo $REPO_NAME exist
    cd $REPO_NAME
    git pull
else
    echo "Repo does not exist, clonning the REPO_URL"
    sleep 1
    git clone -b $BRANCH $REPO_URL
fi

# Prompt for the MariaDB root password.
echo "Please enter the MariaDB root password:"
read -s root_passwd

echo "Configuring MariaDB with the provided root password"

#printf "n\n n\n y\n y\n y\n y\n" | mysql_secure_installation 2>/dev/null
printf "n
 n
 y
 y
 y
 y
" | mysql_secure_installation 2>/dev/null
mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$root_passwd');"
# Ask the Database user for the password.
echo -n "Enter the password for the database user:"
read -s db_passwd

# Mysql variables.
DB_CHECK="$(mysqlshow "$DB_NAME" | grep Database | awk '{print $2}')"

# Creating the database.
if [[ $DB_CHECK == $DB_NAME ]]; then
    echo "Database $DB_NAME exist"
    mysql -e "
    DROP DATABASE $DB_NAME;
    CREATE DATABASE IF NOT EXISTS $DB_NAME;
    CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$db_passwd';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES ;"
    echo "Database $DB_NAME created with user $DB_USER and password."
else
    mysql -e "
    CREATE DATABASE IF NOT EXISTS $DB_NAME;
    CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$db_passwd';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES ;"
    echo "Database $DB_NAME created with user $DB_USER and password."
fi

# Reload MariaDB.
echo "Restarting mariadb"
systemctl restart apache2 mariadb --quiet

# Create a simple php script to test if php is working.
echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# Check if php is working.
PHP_CHECK="$(curl -s http://localhost/info.php | grep phpinfo)"
if [[ $PHP_CHECK == *"phpinfo"* ]]; then
    echo "PHP is working."
else
    echo "PHP is not working."
fi

# Check if index.html exist and rename it to avoid conflicts.
if [ -f /var/www/html/index.html ]; then
    echo "index.html exist"
    mv /var/www/html/index.html /var/www/html/index.html.bk
else
      if [ -f /var/www/html/index.html.bk ]; then
      echo "index.html backed up file exist"
    else
        echo "index.html does not exist"
    fi
fi

# Check if dir.conf file exists and backup the file before editing.
DIRCONF_FILE="/etc/apache2/mods-available/dir.conf"
DIRCONF_PATH="/etc/apache2/mods-available/"

# Change the current directory to DIRCONF_PATH
cd "$DIRCONF_PATH"

if [ -f "$DIRCONF_FILE" ]; then
    echo "$DIRCONF_FILE exists. Creating a backup before editing."
    timestamp=$(date +"%Y%m%d%H%M%S")
    cp "$DIRCONF_FILE" "$DIRCONF_FILE-$timestamp"
    echo "Backup created with filename: $DIRCONF_FILE-$timestamp"

    # Replace the entire DirectoryIndex line in dir.conf
    sed -i "s/^DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" "$DIRCONF_FILE"
    echo "index.php added to the DirectoryIndex in dir.conf."

    # Reload Apache service
    systemctl reload apache2

    # Check if index.php file exist in the DirectoryIndex.
    PHP_INDEX=$(grep -o -m 1 'index.php' "$DIRCONF_FILE")

    if [[ $PHP_INDEX == "index.php" ]]; then
        echo "index.php file exists in the DirectoryIndex. Reloading apache2."
        systemctl reload apache2
    fi
fi

# Changing booking table to allow more digits.
cd $SCRIPT_DIR
DB_SRC="${SCRIPT_DIR}"/bootcamp-devops-2023/app-295devops-travel/database
cd $DB_SRC
sed -i 's/`phone` int(11) DEFAULT NULL,/`phone` varchar(15) DEFAULT NULL,/g' devopstravel.sql

# Copy and verify app data exist in apache root directory.
SRC="${SCRIPT_DIR}"/bootcamp-devops-2023/app-295devops-travel
DEST="/var/www/html/"
if [ -f $DEST/index.php ]; then
    echo "file exist"
else
    cd $SRC
    cp -R ./* "${DEST}"
fi

# Adding database password to config.php.
sed -i "s/\$dbPassword \= \"\";/\$dbPassword \= \"$db_passwd\";/" /var/www/html/config.php 

# Database test and copy.
TABLE_NAME="booking"
TABLE_EXIST=$(mysql -u "$DB_ROOT_USER" -p -e "SHOW TABLES LIKE '$TABLE_NAME'" "$DB_NAME" 2>/dev/null)

# Check if database table exists before copying.
if [[ -n $TABLE_EXIST ]]; then
    echo -e "${LGREEN}Table $TABLE_NAME exists.${NC}"
else
    echo -e "${LRED}Table $TABLE_NAME does not exist.${NC}"
    mysql -u "$DB_ROOT_USER" -p "$DB_NAME" < $DB_SRC/devopstravel.sql
    systemctl restart mariadb
fi

# Creating apache2 firewall profile
dpkg -s ufw > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "ufw Firewall is installed Creating profile for apache2"
    echo "
    [WWW]
    title=Web Server
    description=Web server
    ports=80/tcp

    [WWW Secure]
    title=Web Server (HTTPS)
    description=Web Server (HTTPS)
    ports=443/tcp

    [WWW Full]
    title=Web Server (HTTP,HTTPS)
    description=Web Server (HTTP,HTTPS)
    ports=80,443/tcp

    [WWW Cache]
    title=Web Server (8080)
    description=Web Server (8080)
    ports=8080/tcp" > /etc/ufw/applications.d/ufw-webserver

    # Enabling apache2 firewall profile.
    ufw --force enable
    ufw allow "WWW Full"
    ufw --force reload
else
    echo "ufw firewall is not installed"
fi

# Restarting apache2.
systemctl restart apache2 mariadb > /dev/null 2>&1

# Collect information about installation success or failure
WEBHOOK_URL="https://discordapp.com/api/webhooks/1175907476839874681/MfOT4N73ILoLi8uLAOrn5FGqGOZ9oMWYkfTnyTBE2GbKd9Qr-2vTeVzJ7MxdDzI2L1et"
if [ $? -ep 0 ]; then
    echo -e "${GREEN}295DevOps Travel installacion successfull.${NC}"
    message="295DevOps Travel installation successfull."
else
    echo -e "${LRED}295DevOps Travel installation Failed.${NC}"
    message="295DevOps Travel installation Failed."
fi

# Send Discord notification to my personal deploy-channel
curl -X POST -H "Content-Type: application/json" -d "{\"content\":\"$message\"}" $WEBHOOK_URL
