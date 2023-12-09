#!/bin/bash

# Script directory
SCRIPT_DIR=$(pwd)

DB_DIR="/db_data"
WEB_DIR="/web_data"

#Colors
LRED='\033[1;31m'
LGREEN='\033[1;32m'
NC='\033[0m'

# Creating local container volumes
echo -e "Creating Container volumes if they dont exist"
if [ -d "$DB_DIR" ] && [ -d "$WEB_DIR" ]; then
    echo -e "\n$DB_DIR $WEB_DIR exists"
    sudo rm -rf "$DB_DIR"/*
    sudo rm -rf "$WEB_DIR"/*
else
    mkdir "$DB_DIR" "$WEB_DIR"
fi

# Repo variables
REPO_DIR="$SCRIPT_DIR/bootcamp-devops-2023"
REPO_URL="https://github.com/vramirez0113/bootcamp-devops-2023.git"
REPO_NAME="bootcamp-devops-2023"
BRANCH="ejercicio2-dockeriza"

# Check if script is being run as root.
echo -e "\nChecking if this script is run by root"
if [[ $EUID -ne 0 ]]; then
   echo -e "\n${LRED}This script must be run as root.${NC}"
   exit 1
fi

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

# Add Docker's official GPG key:
DOCKER_GPG="/etc/apt/keyrings/docker.gpg"
sudo apt-get update -qq
if [ -f $DOCKER_GPG ]; then
    echo "\n$DOCKER_GPG exists"
else
    sudo apt-get install -y -qq ca-certificates curl gnupg > /dev/null 2>&1
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi
# Add the repository to Apt sources:
DOCKER_REPO="/etc/apt/sources.list.d/docker.list"
if [ -f $DOCKER_REPO ]; then
    echo "$DOCKER_REPO exists"
else
    echo \
    "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq > /dev/null 2>&1
fi

# Install Apache, mysql, PHP, Curl, Git packages.
packages=("docker-ce" "docker-ce-cli" "containerd.io" "docker-buildx-plugin" "docker-compose" "docker-compose-plugin" "git" "curl" "coreutils")
total_count=${#packages[@]}
package_count=0

for package in "${packages[@]}"; do
    # Check if package is already installed.
    if dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -qq "installed"; then
        package_count=$((package_count + 1))
        progress_bar "$package_count" "$total_count"
        echo -e "\n$package already installed."
    else
        # Install package and show output
        if apt-get install -y -qq "$package" > /dev/null 2>&1; then
            package_count=$((package_count + 1))
            progress_bar "$package_count" "$total_count"
            echo -e "\n${LGREEN}$package installed successfully.${NC}"
        else
            echo -e "\n${LRED}Failed to install $package.${NC}"
            apt-get -y purge "${packages[@]}" -qq
            exit 1
        fi
    fi
done

# Start and enable all services if installation was successful.
if [ $package_count -eq $total_count ]; then
    systemctl start docker --quiet
    systemctl enable docker --quiet
    echo -e "Services started and enabled successfully."
fi

# Prompt for the mysql root password.
echo -e "Please enter the mysql root password:"
read -s db_root_passwd

# Ask the Database user for the password.
echo -n "Please enter the password for the database user:"
read -s db_passwd

# Config Git account
echo -e "\nConfiguring Git account"
git config --global user.name "vramirez0113"
git config --global user.email "vlakstarit@gmail.com"

# Check if app REPO_URL exist before cloning
echo -e "\nChecking if $REPO_NAME exists before cloning"
if [ -d "$REPO_NAME" ]; then
    echo -e "\n$REPO_NAME exists"
    cd "$REPO_NAME"
    git pull
else
    echo -e "\n$REPO_NAME does not exist."
    echo -e "\nCloning $REPO_NAME from $REPO_URL."
    sleep 1
    git clone -b "$BRANCH" "$REPO_URL"
fi

# Changing booking table to allow more digits.
echo -e "\nChanging booking table to allow more digits"
SCRIPT_DIR=$(pwd)
DB_SRC="$SCRIPT_DIR/bootcamp-devops-2023/295devops-travel-lamp/database"
cd "$DB_SRC"
sed -i 's/`phone` int(11) DEFAULT NULL,/`phone` varchar(15) DEFAULT NULL,/g' devopstravel.sql

# Adding database password and container database nane to config.php.
echo -e "\nAdding database password and container database nane to config.php"
DATA_SRC="$SCRIPT_DIR/bootcamp-devops-2023/295devops-travel-lamp"
sed -i "s/\$dbPassword \= \"\";/\$dbPassword \= \"$db_passwd\";/" "$DATA_SRC/config.php"
sed -i 's/$dbHost     \= "localhost";/$dbHost     \= "db";/' "$DATA_SRC/config.php"


# Copy and verify web data exist web_data dir.
echo -e "\nCopy and verify web data exist web_data dir"
if [ -f "$WEB_DIR/index.php" ]; then
    echo "File exists"
else
    cd "$DATA_SRC"
    cp -R ./* "$WEB_DIR"
fi

# Copy and verify database data exist database dir.
echo -e "\nCopy and verify database data exist database dir"
if [ -f "$SCRIPT_DIR/devopstravel.sql" ]; then
    echo "File exists"
else
    cd "$DB_SRC"
    cp devopstravel.sql "$SCRIPT_DIR"
fi

#Login to Docker Hub
echo -e "\nLogin to Docker Hub"
sudo docker login --username=starvlak

# Create a network
sudo docker network create app-network

echo -e "Creating Apache-php container Dockerfile.web"
# Dockerfile to create a custom php-apache image containing mysqli extension
cd "$SCRIPT_DIR"
if [ -f "$SCRIPT_DIR/Dockerfile.web" ]; then
    echo "\nFile exists"
    sudo rm -rf Dockerfile.web
    echo \
    "FROM ubuntu:slim
    # Set environment variables
    ENV DEBIAN_FRONTEND=noninteractive
    # Install dependencies
    RUN apt-get update -y && apt-get install -y \
    apache2 \
    php \
    libapache2-mod-php \
    php-mysql \
    php-mbstring \
    php-zip \
    php-gd \
    php-json \
    php-curl \
    && sed -i 's/^DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf \
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/log/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

    # Expose port 80 for Apache server
    EXPOSE 80

    #Start Apache server
    CMD [\"/usr/sbin/apache2ctl\", \"-D\", \"FOREGROUND\"]" > "$SCRIPT_DIR/Dockerfile.web"
    # To create a custom apache-php image that includes mysqli extensions and push it to Docker Hub
    echo -e "Building and pushing Dockerfile.web to Docker Hub"
    sudo docker build -t starvlak/app-travel:apache2-php_v1.0 -f Dockerfile.web .
    sudo docker push starvlak/app-travel:apache2-php_v1.0
else
    echo \
    "FROM ubuntu:slim
    # Set environment variables
    ENV DEBIAN_FRONTEND=noninteractive
    # Install dependencies
    RUN apt-get update -y && apt-get install -y \
    apache2 \
    php \
    libapache2-mod-php \
    php-mysql \
    php-mbstring \
    php-zip \
    php-gd \
    php-json \
    php-curl \
    && sed -i 's/^DirectoryIndex.*/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g' /etc/apache2/mods-enabled/dir.conf \
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/log/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*
    
    # Expose port 80 for Apache server
    EXPOSE 80

    #Start Apache server
    CMD [\"/usr/sbin/apache2ctl\", \"-D\", \"FOREGROUND\"]" > "$SCRIPT_DIR/Dockerfile.web"
    # To create a custom apache-php image that includes mysqli extensions and push it to Docker Hub
    echo -e "Building and pushing Dockerfile.web to Docker Hub"
    sudo docker build -t starvlak/app-travel:apache2-php_v1.0 -f Dockerfile.web .
    sudo docker push starvlak/app-travel:apache2-php_v1.0
fi

echo -e "Creating Dockerfile.phpmyadmin"
# Dockerfile to create custome phpmyadmin image
if [ -f "$SCRIPT_DIR/Dockerfile.phpmyadmin" ]; then
    echo "File exists"
    sudo  rm -rf Dockerfile.phpmyadmin
    echo \
    "FROM phpmyadmin/phpmyadmin
    ENV PMA_HOST=db
    ENV MYSQL_ROOT_PASSWORD=$db_root_passwd
    ENV MYSQL_DATABASE=devopstravel
    ENV MYSQL_USER=codeuser
    ENV MYSQL_PASSWORD=$db_passwd" > "$SCRIPT_DIR/Dockerfile.phpmyadmin"
    # Build and push phpmyadmin Docker image to Docker Hub
    echo -e "Building and pushing Dockerfile.phpmyadmin to Docker Hub"
    sudo docker build -t starvlak/app-travel:phpmyadmin_v1.0 -f Dockerfile.phpmyadmin .
    sudo docker push starvlak/app-travel:phpmyadmin_v1.0
else
    echo \
    "FROM phpmyadmin/phpmyadmin
    ENV PMA_HOST=db
    ENV MYSQL_ROOT_PASSWORD=$db_root_passwd
    ENV MYSQL_DATABASE=devopstravel
    ENV MYSQL_USER=codeuser
    ENV MYSQL_PASSWORD=$db_passwd" > "$SCRIPT_DIR/Dockerfile.phpmyadmin"
    # Build and push phpmyadmin Docker image to Docker Hub
    echo -e "Building and pushing Dockerfile.phpmyadmin to Docker Hub"
    sudo docker build -t starvlak/app-travel:phpmyadmin_v1.0 -f Dockerfile.phpmyadmin .
    sudo docker push starvlak/app-travel:phpmyadmin_v1.0
fi

echo -e "Creating Dockerfile.db"
# Dockerfile to create a custom mysql image
if [ -f "$SCRIPT_DIR/Dockerfile.db" ]; then
    echo "File exists"
    sudo rm -rf Dockerfile.db
    echo \
    "FROM mysql:latest
    ENV MYSQL_ROOT_PASSWORD=$db_root_passwd
    ENV MYSQL_DATABASE=devopstravel
    ENV MYSQL_USER=codeuser
    ENV MYSQL_PASSWORD=$db_passwd
    # Copy the devopstravel.sql file to the container
    COPY devopstravel.sql /docker-entrypoint-initdb.d/" > "$SCRIPT_DIR/Dockerfile.db"
    # Build and push Mysql Docker image to Docker Hub
    echo -e "Building and pushing Dockerfile.db to Docker Hub"
    sudo docker build -t starvlak/app-travel:mysql_v1.0 -f Dockerfile.db .
    sudo docker push starvlak/app-travel:mysql_v1.0
else
    echo \
    "FROM mysql:latest
    ENV MYSQL_ROOT_PASSWORD=$db_root_passwd
    ENV MYSQL_DATABASE=devopstravel
    ENV MYSQL_USER=codeuser
    ENV MYSQL_PASSWORD=$db_passwd
    # Copy the devopstravel.sql file to the container
    COPY devopstravel.sql /docker-entrypoint-initdb.d/" > "$SCRIPT_DIR/Dockerfile.db"
    # Build and push Mysql Docker image to Docker Hub
    echo -e "Building and pushing Dockerfile.db to Docker Hub"
    sudo docker build -t starvlak/app-travel:mysql_v1.0 -f Dockerfile.db .
    sudo docker push starvlak/app-travel:mysql_v1.0
fi

echo -e "Creating docker-compose.yml"
# Docker compose file
echo \
"version: '3.8'
services:
    db:
        build:
            context: .
            dockerfile: Dockerfile.db
        image: starvlak/app-travel:mysql_v1.0
        container_name: db
        environment:
            - MYSQL_ROOT_PASSWORD=${db_root_passwd}
            - MYSQL_DATABASE=devopstravel
            - MYSQL_USER=codeuser
            - MYSQL_PASSWORD=${db_passwd}
        volumes:
            - type: bind
              source: /db_data
              target: /var/lib/mysql
        networks:
            - app-network

    web:
        build:
            context: .
            dockerfile: Dockerfile.web
        image: starvlak/app-travel:apache2-php_v1.0
        container_name: web
        depends_on:
            - db
        ports:
            - 80:80
        volumes:
            - type: bind
              source: /web_data
              target: /var/www/html
        networks:
            - app-network

    phpmyadmin:
        build:
            context: .
            dockerfile: Dockerfile.phpmyadmin
        image: starvlak/app-travel:phpmyadmin_v1.0
        container_name: phpmyadmin
        depends_on:
            - db
        ports:
            - 8080:80
        environment:
            - PMA_HOST=db
            - PMA_PORT=3306
            - PMA_USER=root
            - PMA_PASSWORD=${db_root_passwd}
            - PMA_ARBITRARY=1
        networks:
            - app-network

networks:
    app-network:
        driver: bridge" > docker-compose.yml

# Run docker-compose
sudo docker-compose up -d

# Container names
containers=("web" "db" "phpmyadmin")

# Check if all containers are up and running
echo -e "\nChecking if all containers are up and running"
for container in "${containers[@]}"; do
    docker ps | grep -q $container
    if [ $? -eq 0 ]; then
        echo -e "\n${LGREEN}Container $container is running.${NC}"
    else
        echo -e "\n${LRED}Container $container is not running.${NC}"
        exit 1
    fi
done

# Check if web app is running
echo -e "Checking if web app is running"
curl -s http://localhost:80 | grep 295DevOps | echo -e "\n"295DevOps Travel app is running"
if [ $? -eq 0 ]; then
    echo -e "\n${LGREEN}295DevOps Travel app is running.${NC}"
else
    echo -e "\n${LRED}295DevOps Travel app is not running.${NC}"
fi

# Collect information about installation success or failure
WEBHOOK_URL="https://discordapp.com/api/webhooks/1182933054046613584/MNmdYzvvl6l5gSznSyzbGeU12C56bTm71frnJ6fDLBFJuZtB7dEHZjwGtWV9OO6wqRRb"
if [ $? -eq 0 ]; then
    echo -e "\n${LGREEN}295DevOps Travel installation successful.${NC}"
    message="$REPO_URL $BRANCH 295DevOps Travel installation successful."
else
    echo -e "\n${LRED}295DevOps Travel installation Failed.${NC}"
    message="$REPO_URL $BRANCH 295DevOps Travel installation successful."
fi

# Send Discord notification to my personal deploy-channel
curl -X POST -H "Content-Type: application/json" -d "{\"content\":\"$message\"}" "$WEBHOOK_URL"
