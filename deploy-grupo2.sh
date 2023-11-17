#!/bin/bash -x
set -e

# Repository variable
repo="bootcamp-devops-2023"

# MySQL root credentials
db_root_user="root"
#db_root_passwd="abcde12345"

# Database and user details variables
db_name="devopstravel"
db_user="codeuser"
#db_user_passwd="123456"

echo "Checking if this script is run by root"
#check if script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Updating packages index"
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

# Install Apache, MariaDB,PHP, Curl, Git packages
packages=("apache2" "mariadb-server" "php" "libapache2-mod-php" "php-mysql" "php-mbstring" "php-zip" "php-gd" "php-json" "php-curl" "curl" "git")
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
apt-get install -y -qq "$package" > /dev/null 2>&1

# Check if installation was successful
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
    mv /var/www/html/index.html /var/www/html/index.html.bk
else
    echo "index.html files does not exist"
fi

# Check if dir.conf file exists
dirconf_path="/etc/apache2/mods-available/"
dirconf_file="dir.conf"
cd $dirconf_path
if [ -f "${dirconf_file}" ]; then
    echo "$dirconf_file exist creating a backup before editing."
    cp "${dirconf_file}" "${dirconf_file}.bk"
    sed -i "s/DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" "${dirconf_file}"
    echo "index.php added to the DirectoryIndex in dir.conf."
else
    echo "The dir.conf file does not exist. Please re-install apache2."
fi

if [[ $php_index == "index.php" ]]; then
    echo "index.php file exist. Reloading apache2"
    systemctl reload apache2 --quiet
fi


# Prompt for the MariaDB root password (esta parte se habilitara luego)
echo "Please enter the MariaDB root password:"
read -s root_passwd

echo "Configuring MariaDB with the provided root password"

printf "n\n n\n y\n y\n y\n y\n" | mysql_secure_installation
mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('$root_passwd');"
# Ask the Database user for the password
echo -n "Enter the password for the database user:"
read -s db_passwd
echo

#Mysql variables
db_check=$(mysqlshow "$db_name" | grep Database | awk '{print $2}')


# Creating the database
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

# Changing booking table to allow more digits
db_src="/home/vladram/devops295/clase2-linux/bootcamp-devops-2023/app-295devops-travel/database"
cd $db_src
sed -i 's/`phone` int(11) DEFAULT NULL,/`phone` varchar(15) DEFAULT NULL,/g' devopstravel.sql

# Copy and verify app data exist in apache root directory
src="/home/vladram/devops295/clase2-linux/bootcamp-devops-2023/app-295devops-travel"
dest="/var/www/html/"
if [ -f $dest/index.php ]; then
    echo "file exist"
else
    cd $src
    cp -R ./* "${dest}"
fi

# Adding database password to config.php
sed -i "s/\$dbPassword \= \"\";/\$dbPassword \= \"$db_passwd\";/" /var/www/html/config.php 

# Test if php.info is successful
php_info=$(curl -s localhost/info.php | grep phpinfo)
if [[ $php_info == *"phpinfo"* ]]; then
    echo "info.php test successful."
else
    echo "info.php test failed."
fi

#Database test and copy
TABLE_NAME=booking
TABLE_EXIST=$(printf 'SHOW TABLES LIKE "%s"' "$TABLE_NAME")
# Execute the query and check the result
if [[ $(mysql -u $db_root_user -p -e "$TABLE_EXIST" $db_name) ]]; then
    echo -e "${LGREEN}Table $TABLE_NAME exists.${NC}"
else
    echo -e "${LRED}Table $TABLE_NAME does not exist.${NC}"
    cd ${db_src}
    mysql < devopstravel.sql
    systemctl restart mariadb
fi

dpkg -s ufw > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "ufw Firewall is installed"
    ufw --force enable
    ufw allow "WWW Full"
    ufw --force reload
else
    echo "Installing  UFW Firewall"
    apt install -y ufw -qq
    ufw --force enable
    ufw allow "WWW Full"
    ufw --force reload
fi

# Restarting apache2
systemctl restart apache2
echo "295DevOps Travel installation successfull"
echo "Please go to http://localhost to test"
