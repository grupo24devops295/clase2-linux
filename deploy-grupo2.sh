#!/bin/bash -x
set -e

# Repository
repo="bootcamp-devops-2023"

# MySQL root credentials
db_root_user="root"
db_root_passwd="abcde12345"

# Database and user details
db_name="devopstravel"
db_user="codeuser"
db_user_passwd="123456"

echo "Cheching if this script is run by root"
#check if script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Function to check if package is already installed
is_installed() {
  dpkg -s $1 &> /dev/null
}

echo "Checking for update before install"
# Update the package list
apt update

# Check if Git is installed or not
if ! is_installed git; then
  echo "Installing Git"
  apt -qq install -y git
fi

# Check if Curl is installed or not
if ! is_installed curl; then
  echo "Installing Curl"
  apt -qq install -y curl
fi

# Check if MariaDB is installed or not
if ! is_installed mariadb-server; then
  echo "Installing MariaDB"
  apt -qq install -y mariadb-server

# Enable and start MariaDB
systemctl enable mariadb
systemctl start mariadb

# Prompt for the MariaDB root password (esta parte se habilitara luego)
#echo "Please enter the MariaDB root password:"
#read -s root_passwd

#echo "Configuring MariaDB with the provided root password"

#printf "n\n n\n y\n y\n y\n y\n" | mysql_secure_installation
#mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$root_passwd');"
# Ask the Database user for the password
#echo -n "Enter the password for the database user: "
#read -s db_passwd
#echo

# Creating the database
mysql -e "
CREATE DATABASE IF NOT EXISTS $db_name;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_passwd';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES ;"
echo "Database $db_name created with user $db_user and password."
fi

# Check if Apache is installed or not
if ! is_installed apache2; then
  echo "Installing  Apache"
  apt -qq install -y apache2

#Rename apache2 index.html
mv /var/www/html/index.html /var/www/html/index.html.bk

# Enable and start Apache
systemctl enable apache2
systemctl start apache2
fi

# Check if PHP is installed or not
if ! is_installed php; then
 echo "Installing PHP"
  apt -qq install -y php libapache2-mod-php php-mysql
fi
# Path to dir.conf file
dirconf_file="/etc/apache2/mods-enabled/dir.conf"

# Check if dir.conf file exists
if [ ! -f "$dirconf_file" ]; then
    echo "The dir.conf file does not exist."
    exit 1
fi

# Modify dir.conf file
sed -i 's/DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/' $dirconf_file
echo "index.php added to the DirectoryIndex in dir.conf."

# Restart Apache
systemctl restart apache2

if [ -d "$repo" ]; then
    echo $repo exist
    cd $repo
    git pull
else
    echo "Repo does not exist, clonning the repo"
    sleep 1
    git clone -b clase2-linux-bash https://github.com/roxsross/bootcamp-devops-2023.git
fi

cp -r $repo/app-295devops-travel/* /var/www/html
mysql < bootcamp-devops-2023/app-295devops-travel/database/devopstravel.sql

#Agregar apache2 al firewall ufw opcional para cada quien
# Check if UFW firewall is installed or not
if ! is_installed ufw; then
  echo "Installing  UFW Firewall"
  apt -qq install -y ufw
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
ports=8080/tcp > /etc/ufw/applications.d/ufw-webserver
ufw enable
ufw allow "WWW Full" 
systemctl reload ufw

#Restart apache2 service
systemctl reload apache2

echo "Testing if installation was successful
if is_installed apache2 && is_installed mariadb-server && is_installed php && is_installed git && is_installed curl; then
  echo "LAMP installation successful!"
else
  echo "LAMP installation failed!"
fi




