#!/bin/bash
set -e

# Repository variable
repo="bootcamp-devops-2023"

# MySQL root credentials
db_root_user="root"
db_root_passwd="abcde12345"

# Database and user details variables
db_name="devopstravel"
db_user="codeuser"
db_user_passwd="123456"
dirconf_file='/etc/apache2/mods-enabled/dir.conf'

echo "Checking if this script is run by root"
#check if script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Checking for update before install"
# Update the package list
apt update -qq

# Function to display progress bar
function progress_bar() {
  local current=$1
  local total=$2
  local percent=$((current * 100 / total))
  local bar_length=30

  printf "%s " "$percent" | awk '{printf("\r[%-30s] %d%%", substr("##############################", 1, ($1/10)+0.5), $1)}'
}

# Install Apache packages
packages=("apache2" "mariadb-server" "php" "pv" "libapache2-mod-php" "php-mysql" "php-mbstring" "php-zip" "php-gd" "php-json" "php-curl" "curl" "git")
total_count=${#packages[@]}
package_count=0

for package in "${packages[@]}"; do
  # Check if package is already installed
  if dpkg -s "$package" > /dev/null 2>&1; then
    package_count=$((package_count+1))
    progress_bar "$package_count" "$total_count"
    echo " $package already installed."

  else
    # Install package
     apt-get install -y -qq "$package $firewall" > /dev/null 2>&1

    # Check if installation was successful
    if [ $? -eq 0 ]; then
      package_count=$((package_count+1))
      progress_bar "$package_count" "$total_count"
      echo " $package installed successfully."
    else
      echo "Failed to install $package. Removing packages..."
      apt-get -y purge "${packages[@]}" -qq
      exit 1
    fi
  fi
done

# Start and enable all services if installation was successful
if [ $package_count -eq $total_count ]; then
  sudo systemctl start apache2 --quiet
  sudo systemctl enable apache2 --quiet
  sudo systemctl start mariadb --quiet
  sudo systemctl enable mariadb --quiet
  echo "Services started and enabled successfully."
fi

# Path for apache file and php
php_index="grep DirectoryIndex $dirconfig_file | awk '{print $2}'"

if [ -f /var/www/html/index.html ]; then
    echo "index.html exist"
    mv /var/www/html/index.html | pv -p -t | /var/www/html/index.html.bk
else
    echo "index.html is now index.html.bk"
fi

# Check if dir.conf file exists
if [ ! -f "$dirconf_file" ]; then
    echo "The dir.conf file does not exist. Please re-install"
    exit 1
else
    sed -i 's/DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/' $dirconf_file
    echo "index.php added to the DirectoryIndex in dir.conf."
fi

if [[ $php_index == "index.php" ]]; then
    echo "index.php file exist. Reloading apache2"
    systemctl reload apache2 --quiet
fi


# Prompt for the MariaDB root password (esta parte se habilitara luego)
#echo "Please enter the MariaDB root password:"
#read -s root_passwd

#echo "Configuring MariaDB with the provided root password"

#printf "n\n n\n y\n y\n y\n y\n" | mysql_secure_installation
#mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$root_passwd');"
# Ask the Database user for the password
#echo -n "Enter the password for the database user:"
#read -s db_passwd
#echo

#Mysql variables
db_check=$(mysqlshow "$db_name" | grep Database | awk '{print $2}')


# Creating the database
if [ $db_check == $db_name ]; then
   echo "Database $db_name exist"
else
    mysql -e "
    CREATE DATABASE IF NOT EXISTS $db_name;
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_passwd';
    GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES ;"
    echo "Database $db_name created with user $db_user and password."
fi

# Reload MariaDB
echo "Restarting mariadb"
systemctl restart apache2 mariadb --quiet

if [ -d "$repo" ]; then
    echo $repo exist
    cd $repo
    git pull
else
    echo "Repo does not exist, clonning the repo"
    sleep 1
    git clone -b clase2-linux-bash https://github.com/roxsross/bootcamp-devops-2023.git
fi

if [ -f /var/www/html/index.php ]; then
echo "file exist"
else
cp -r $repo/app-295devops-travel/* | pv | /var/www/html/
fi

# Test if php.info is successful
php_info=$(curl -s localhost/info.php | grep phpinfo)
if [[ $php_info == *"phpinfo"* ]]; then
  echo "info.php test successful."
else
  echo "info.php test failed."
fi

if [ -d /var/www/html/database ]; then
echo "$db_name databse exist"
else
mysql < bootcamp-devops-2023/app-295devops-travel/database/devopstravel.sql
fi

#Check if ufw firewall is present
#for i in ufw; do

dpkg -s ufw > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "ufw Firewall is installed"
  ufw --force enable
  ufw allow "WWW Full"
  ufw --force reload
else
  echc "Installing  UFW Firewall"
  apt install -y ufw -qq
  ufw --force enable
  ufw allow "WWW Full"
  ufw --force reload
fi

#echo "Testing if installation was successful"
#if is_installed apache2 && is_installed mariadb-server && is_installed php && is_installed git && is_installed curl; then
#  echo "LAMP installation successful!"
#else
#  echo "LAMP installation failed!"
#fi




