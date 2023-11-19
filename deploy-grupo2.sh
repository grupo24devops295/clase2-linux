#!/bin/bash -x
#set -e

# MySQL root credentials
db_root_user="root"

# Database and user details variables.
db_name="devopstravel"
db_user="codeuser"

# Script directory
script_dir=$(pwd)

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
  local bar_length=100

  printf "%s " "$percent" | awk '{printf("\r[%-30s] %d%%", substr("##############################", 1, ($1/20)+0.5), $1)}'
}

# Install Apache, MariaDB,PHP, Curl, Git packages.
packages=("apache2" "mariadb-server" "php" "libapache2-mod-php" "php-mysql" "php-mbstring" "php-zip" "php-gd" "php-json" "php-curl" "curl" "git")
total_count=${#packages[@]}
package_count=0

for package in "${packages[@]}"; do
# Check if package is already installed.
    if dpkg -s "$package" > /dev/null 2>&1; then
        package_count=$((package_count+1))
        progress_bar "$package_count" "$total_count"
        echo " $package already installed."
    else
        # Install package
        apt-get install -y -qq "$package" > /dev/null 2>&1

        # Check if installation was successful.
        if [ $? -eq 0 ]; then
            package_count=$((package_count+1))
            progress_bar "$package_count" "$total_count"
            echo "$package installed successfully."
        else
            echo "Failed to install $package. Removing packages..."
            apt-get -y purge "${packages[@]}" -qq
            exit 1
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
repo="https://github.com/vramirez0113/bootcamp-devops-2023.git"
repo_dir="~/bootcam-devops-2023"
#branch="clase2-linux-bash"

# Config Git account
git config --global user.name "vramirez0113"
git config --global user.email "vlakstarit@gmail.com"

# Check if app repo exist before cloning
if [ -d "$repo_dir" ]; then
    echo $repo_dir exist
    cd $repo_dir
    git pull
else
    echo "Repo does not exist, clonning the repo"
    sleep 1
    git clone -b clase2-linux-bash $repo
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
db_check="$(mysqlshow "$db_name" | grep Database | awk '{print $2}')"

# Creating the database.
if [[ $db_check == $db_name ]]; then
    echo "Database $db_name exist"
    mysql -e "
    DROP DATABASE $db_name;
    CREATE DATABASE IF NOT EXISTS $db_name;
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_passwd';
    GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES ;"
    echo "Database $db_name created with user $db_user and password."
else
    mysql -e "
    CREATE DATABASE IF NOT EXISTS $db_name;
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_passwd';
    GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES ;"
    echo "Database $db_name created with user $db_user and password."
fi

# Reload MariaDB.
echo "Restarting mariadb"
systemctl restart apache2 mariadb --quiet

# Create a simple php script to test if php is working.
echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# Check if php is working.
php_check="$(curl -s http://localhost/info.php | grep phpinfo)"
if [[ $php_check == *"phpinfo"* ]]; then
    echo "PHP is working."
else
    echo "PHP is not working."
    exit 1
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
dirconfig_file="/etc/apache2/mods-available/dir.conf"
dirconf_path="/etc/apache2/mods-available/"
cd $dirconf_path
if [ -f "${dirconf_file}" ]; then
    echo "$dirconf_file exist creating a backup before editing."
    cp "${dirconf_file}" "${dirconf_file}"-bk
    sed -i "s/DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" "${dirconf_file}"
    echo "index.php added to the DirectoryIndex in dir.conf."
    systemctl reload apache2 --quiet

    # Check if index.php file exist in the DirectoryIndex.
    #echo "Checking if index.php file exist in the DirectoryIndex."
    #php_index=$(grep DirectoryIndex "${dirconfig_file}" | awk '{print $2}')
    #if [[ $php_index == "index.php" ]]; then
    #    echo "index.php file exist. Reloading apache2"
    #    systemctl reload apache2 --quiet
    #fi
    #exit 1
fi 

# Changing booking table to allow more digits.
cd $script_dir
db_src="${script_dir}"/bootcamp-devops-2023/app-295devops-travel/database
cd $db_src
sed -i 's/`phone` int(11) DEFAULT NULL,/`phone` varchar(15) DEFAULT NULL,/g' devopstravel.sql

# Copy and verify app data exist in apache root directory.
src="~/bootcamp-devops-2023/app-295devops-travel"
dest="/var/www/html/"
if [ -f $dest/index.php ]; then
    echo "file exist"
else
    cd $src
    cp -R ./* "${dest}"
fi

# Adding database password to config.php.
sed -i "s/\$dbPassword \= \"\";/\$dbPassword \= \"$db_passwd\";/" /var/www/html/config.php 

# Database test and copy.
TABLE_NAME=booking
TABLE_EXIST=$(printf 'SHOW TABLES LIKE "%s"' "$TABLE_NAME")

# Check if database exist before copying.
if [[ $(mysql -u $db_root_user -p -e "$TABLE_EXIST" $db_name) ]]; then
    echo -e "${LGREEN}Table $TABLE_NAME exists.${NC}"
else
    echo -e "${LRED}Table $TABLE_NAME does not exist.${NC}"
    cd ${db_src}
    mysql < devopstravel.sql
    systemctl restart mariadb
fi

# Creating apache2 firewall profile
dpkg -s ufw > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "ufw Firewall is installed Creating profile for apache2"
    cat > ufw-webserver <<- EOF
    # /etc/ufw/applications.d/ufw-webserver
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
    ports=8080/tcp
    EOF 
    # Copying ufw-webserver profile to ufw applications directory.
    cp ufw-webserver /etc/ufw/applications.d/ufw-webserver

    # Enabling apache2 firewall profile.
    ufw --force enable
    ufw allow "WWW Full"
    ufw --force reload
else
    echo "ufw firewall is not installed"
fi

# Restarting apache2.
systemctl restart apache2
echo "295DevOps Travel installation successfull"
echo "Please go to http://localhost to test"