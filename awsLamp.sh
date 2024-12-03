#!/bin/bash

###########################################
# AWS LAMP Stack Deployment Script
# 
# This script automates the deployment of a LAMP stack on AWS.
# It can optionally install:
# - Basic LAMP (Linux, Apache, MySQL, PHP)
# - SFTP access
# - VS Code server
# - Database management tools
# - WordPress
# - Matomo Analytics
###########################################

###########################################
# Configuration Variables
###########################################
TIMEOUT=120                    # Maximum wait time for instance startup (seconds)
MAX_RETRIES=3                  # Maximum retry attempts for operations
INSTANCE_TYPE="t2.medium"      # AWS instance type
SSH_KEY_NAME="key_WebServerAuto"
SECURITY_GROUP_NAME="webServerSecurityGroup"
INSTANCE_TAG_NAME="myWebServerAuto"
ELASTIC_IP_TAG_NAME="elasticIPWebServerAuto"

# Feature flags
INSTALL_LAMP=false
INSTALL_SFTP=false
INSTALL_VSCODE=false
INSTALL_DB=false
INSTALL_WORDPRESS=false
INSTALL_MATOMO=false

###########################################
# Helper Functions
###########################################

# Function to show spinner while waiting
show_spinner() {
    local message="$1"
    echo -en "\r\033[K$message"
    for cursor in '/' '-' '\' '|'; do
        echo -en "\b$cursor"
        sleep 0.5
    done
}

# Function to check resource status
wait_for_termination() {
    local resource_id="$1"
    local resource_type="$2"
    # ...existing status check code...
}

###########################################
# Command Line Argument Processing
###########################################
# Parse command line arguments. If no arguments are provided, the script will only install LAMP.
# -lamp: Install LAMP
# -sftp: Install LAMP and enable root login for SFTP
# -vscode: Install LAMP, enable root login for SFTP and install VS Code
# -db: Install LAMP, enable root login for SFTP, install VS Code and install Adminer and phpMyAdmin
# -wp: Install LAMP, enable root login for SFTP, install VS Code, install Adminer and phpMyAdmin and install WordPress
for arg in "$@"
do
    case $arg in
        -lamp)
        INSTALL_LAMP=true
        shift
        ;;
        -sftp)
        INSTALL_LAMP=true
        INSTALL_SFTP=true
        shift
        ;;
        -vscode)
        INSTALL_LAMP=true
        INSTALL_SFTP=true
        INSTALL_VSCODE=true
        shift
        ;;
        -db)
        INSTALL_LAMP=true
        INSTALL_SFTP=true
        INSTALL_VSCODE=true
        INSTALL_DB=true
        shift
        ;;
        -wp)
        INSTALL_LAMP=true
        INSTALL_SFTP=true
        INSTALL_VSCODE=true
        INSTALL_DB=true
        INSTALL_WORDPRESS=true
        shift
        ;;
        -mt)
        INSTALL_LAMP=true
        INSTALL_SFTP=true
        INSTALL_VSCODE=true
        INSTALL_DB=true
        INSTALL_WORDPRESS=true
        INSTALL_MATOMO=true
        shift
        ;;
    esac
done

###########################################
# Cleanup Phase
###########################################
printf "\e[3;4;31mStarting cleanup of AWS resources...\e[0m\n"

# 1. Clean up Elastic IPs
echo "1. Cleaning up Elastic IPs..."
EXISTING_ELASTIC_IP_ALLOCATION_IDS=$(aws ec2 describe-tags \
    --filters "Name=key,Values=Name" "Name=value,Values=elasticIPWebServerAuto" "Name=resource-type,Values=elastic-ip" \
    --query 'Tags[*].ResourceId' \
    --output text)

if [ -n "$EXISTING_ELASTIC_IP_ALLOCATION_IDS" ]; then
    echo " - Found existing Elastic IPs, releasing..."
    for ALLOCATION_ID in $EXISTING_ELASTIC_IP_ALLOCATION_IDS; do
        aws ec2 release-address --allocation-id $ALLOCATION_ID
        echo " - Released Elastic IP with allocation ID: $ALLOCATION_ID"
    done
else
    echo " - No existing Elastic IPs found"
fi

# 2. Clean up EC2 instances
echo "2. Cleaning up EC2 instances..."
EXISTING_INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=myWebServerAuto" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ -n "$EXISTING_INSTANCE_IDS" ]; then
    echo " - Found existing instances, terminating..."
    aws ec2 terminate-instances --instance-ids $EXISTING_INSTANCE_IDS > /dev/null
    echo " - Termination initiated for instances: $EXISTING_INSTANCE_IDS"
    echo " - Waiting for instances to terminate..."
    
    # Show progress while waiting for termination
    while true; do
        STATUS=$(aws ec2 describe-instances \
            --instance-ids $EXISTING_INSTANCE_IDS \
            --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
            --output text)
        
        # Clear previous line and show current status
        echo -en "\r\033[K - Current status:"
        while IFS=$'\t' read -r id state; do
            echo -n " $id: $state"
        done <<< "$STATUS"
        
        # Check if all instances are terminated
        if ! echo "$STATUS" | grep -qv "terminated"; then
            echo -e "\n - All instances terminated successfully"
            break
        fi
        
        # Show spinning cursor
        for cursor in '/' '-' '\' '|'; do
            echo -en "\b$cursor"
            sleep 0.5
        done
    done
else
    echo " - No existing instances found"
fi

# 3. Clean up security groups
echo "3. Cleaning up security groups..."
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
    --group-names webServerSecurityGroup \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ -n "$EXISTING_SG_ID" ] && [ "$EXISTING_SG_ID" != "None" ]; then
    echo " - Found existing security group, checking dependencies..."
    
    # Wait for any instances using the security group to terminate
    while true; do
        DEPENDENT_INSTANCES=$(aws ec2 describe-instances \
            --filters "Name=instance.group-id,Values=$EXISTING_SG_ID" "Name=instance-state-name,Values=running,pending,stopping,stopped,shutting-down" \
            --query 'Reservations[*].Instances[*].InstanceId' \
            --output text)
            
        if [ -z "$DEPENDENT_INSTANCES" ]; then
            break
        fi
        echo " - Waiting for dependent instances to terminate..."
        sleep 5
    done
    
    # Try to delete the security group
    for i in 1 2 3; do
        if aws ec2 delete-security-group --group-id $EXISTING_SG_ID 2>/dev/null; then
            echo " - Security group deleted successfully"
            break
        else
            if [ $i -eq 3 ]; then
                echo "Failed to delete security group after 3 attempts. Please check AWS Console and try again."
                exit 1
            fi
            echo " - Deletion attempt $i failed, waiting ${i}0 seconds..."
            sleep $((i * 10))
        fi
    done
else
    echo " - No existing security group found"
fi

# 4. Clean up SSH keys
echo "4. Cleaning up SSH keys..."
if aws ec2 describe-key-pairs --key-name key_WebServerAuto >/dev/null 2>&1; then
    echo " - Found existing key pair, removing..."
    # Remove from AWS
    aws ec2 delete-key-pair --key-name key_WebServerAuto > /dev/null
    # Remove local files
    rm -f ~/.ssh/key_WebServerAuto* ~/.ssh/known_hosts* ~/.ssh/config
    echo " - Removed key pair and local SSH files"
    # Wait a moment for AWS to process the deletion
    sleep 2
else
    echo " - No existing key pair found"
fi

###########################################
# Resource Creation Phase
###########################################

# 1. Create security group and configure ports
echo "Creating new security group..."
# Try to create security group with retries
for i in 1 2 3; do
    SG_ID=$(aws ec2 create-security-group \
        --group-name webServerSecurityGroup \
        --description "Web Server security group" \
        --query 'GroupId' \
        --output text 2>/dev/null) && break
    echo " - Creation attempt $i failed, waiting ${i}0 seconds..."
    sleep $((i * 10))
    if [ $i -eq 3 ]; then
        echo "Failed to create security group after 3 attempts. Exiting..."
        exit 1
    fi
done

echo "Successfully created security group: $SG_ID"

echo "Opening required ports..."
echo " - Opening SSH (port 22)"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 > /dev/null

echo " - Opening HTTP (port 80)"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 > /dev/null

echo " - Opening HTTPS (port 443)"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 > /dev/null

echo " - Opening RDP (port 3389)"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 3389 \
    --cidr 0.0.0.0/0 > /dev/null

echo " - Opening Code Server (port 8080)"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 > /dev/null

# 2. Create and configure SSH key pair
echo "Creating new key pair..."
# Try to create key pair with retries
for i in 1 2 3; do
    if mkdir -p ~/.ssh && \
       aws ec2 create-key-pair \
           --key-name key_WebServerAuto \
           --query 'KeyMaterial' \
           --output text > ~/.ssh/key_WebServerAuto 2>/dev/null; then
        chmod 600 ~/.ssh/key_WebServerAuto
        echo " - Key pair created successfully"
        break
    else
        if [ $i -eq 3 ]; then
            echo "Failed to create key pair after 3 attempts. Exiting..."
            exit 1
        fi
        echo " - Creation attempt $i failed, waiting ${i}0 seconds..."
        sleep $((i * 10))
    fi
done

# 3. Launch EC2 instance
echo Finding the latest Ubuntu Server Linux AMI in the current region...
aws ec2 describe-images \
    --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server*' \
              'Name=state,Values=available' \
              'Name=virtualization-type,Values=hvm' \
              'Name=architecture,Values=x86_64' \
    --query 'sort_by(Images, &CreationDate)[-1].Description' \
    --output text

# Print the latest Ubuntu Server Linux version details
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server*' \
              'Name=state,Values=available' \
              'Name=virtualization-type,Values=hvm' \
              'Name=architecture,Values=x86_64' \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
    
echo "Creating instance..."
# Fix instance creation command
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type t2.medium \
    --key-name key_WebServerAuto \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=myWebServerAuto}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo "Failed to create instance"
    exit 1
fi

echo "Waiting for instance to be ready..."
start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    
    if [ $elapsed_time -gt $TIMEOUT ]; then
        echo -e "\nTimeout waiting for instance to be ready after $((TIMEOUT/60)) minutes"
        exit 1
    fi
    
    STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    printf "\rCurrent state: %-10s Time: %ds" "$STATE" "$elapsed_time"
    
    if [ "$STATE" = "running" ]; then
        echo -e "\nInstance is running..."
        # Give a few seconds for SSH to be ready
        sleep 10
        break
    elif [ "$STATE" = "terminated" ] || [ "$STATE" = "shutting-down" ]; then
        echo -e "\nError: Instance terminated unexpectedly"
        exit 1
    fi
    
    sleep 2
done

# 4. Configure Elastic IP
echo "Allocating a new Elastic IP..."
ALLOCATION_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --query 'AllocationId' \
    --output text)

echo "Tagging Elastic IP..."
aws ec2 create-tags \
    --resources "$ALLOCATION_ID" \
    --tags Key=Name,Value=elasticIPWebServerAuto

echo "Getting Elastic IP address..."
ELASTIC_IP=$(aws ec2 describe-addresses \
    --allocation-ids "$ALLOCATION_ID" \
    --query 'Addresses[0].PublicIp' \
    --output text)

echo "Associating Elastic IP with the new instance..."
aws ec2 associate-address \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$ALLOCATION_ID" > /dev/null

echo "Host vm
    HostName $ELASTIC_IP
    User ubuntu
    IdentityFile ~/.ssh/key_WebServerAuto" > ~/.ssh/config
    
echo "Attempting to establish SSH connection..."
count=0
while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ~/.ssh/key_WebServerAuto ubuntu@$ELASTIC_IP 'exit' 2>/dev/null
do
    count=$((count+1))
    printf "\rAttempt %d/%d " $count $MAX_RETRIES
    if [ $count -eq $MAX_RETRIES ]; then
        echo -e "\nFailed to establish SSH connection after $MAX_RETRIES attempts"
        exit 1
    fi
    sleep 2
done
echo -e "\nSSH connection established!"

###########################################
# Installation Phase
###########################################

echo "Starting software installation..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/key_WebServerAuto ubuntu@$ELASTIC_IP \
'\
set -e

#----------------
# LAMP Stack
#----------------
if [ '$INSTALL_LAMP' = true ]; then
    echo "Updating apt repos..."
    sudo apt-get -q update

    echo Installing LAMP...
    sudo apt-get -qqfy install apache2 mysql-server php

    echo Configuring LAMP...
    sudo sed -i.bak -e "s/DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" /etc/apache2/mods-enabled/dir.conf
    sudo wget https://raw.githubusercontent.com/danielcregg/simple-php-website/main/index.php -P /var/www/html/
    sudo rm -rf /var/www/html/index.html
    sudo chown -R www-data:www-data /var/www
    sudo systemctl restart apache2
fi

#----------------
# SFTP Access
#----------------
if [ '$INSTALL_SFTP' = true ]; then
    echo Enabling root login for SFTP...
    sudo sed -i "/PermitRootLogin/c\PermitRootLogin yes" /etc/ssh/sshd_config
    sudo echo -e "tester\ntester" | sudo passwd root
    sudo systemctl restart sshd
fi

#----------------
# VS Code Server
#----------------
if [ '$INSTALL_VSCODE' = true ]; then
    echo "Enable Vscode tunnel login via browser..." 
    #sudo wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    #sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    #sudo sh -c "echo 'deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main' > /etc/apt/sources.list.d/vscode.list"
    #sudo apt-get -qq update
    #sudo apt-get -qqy install code 2>/dev/null
    #sudo rm -rf packages.microsoft.gpg
    #code --install-extension ms-vscode.remote-server 2>/dev/null
    # local code-server install
    #sudo apt-get install -y build-essential
    #curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    #sudo apt-get install -y nodejs
    #sudo npm install -g code-server --unsafe-perm
    #sudo nohup code-server --auth none --bind-addr 0.0.0.0:8080 /var/www/html &
    #code tunnel service --accept-server-license-terms
    #cd /var/www/html/;sudo code tunnel --accept-server-license-terms --no-sleep
fi

#----------------
# Database Tools
#----------------
if [ '$INSTALL_DB' = true ]; then
    echo Installing Adminer...
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install adminer 2>/dev/null
    echo Configuring Andminer
    sudo a2enconf adminer
    sudo mysql -Bse "CREATE USER IF NOT EXISTS admin@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON *.* TO admin@localhost;FLUSH PRIVILEGES;"
    sudo systemctl reload apache2

    echo Install phpmyadmin...
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password 'password'"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password 'password'"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/internal/skip-preseed boolean true"
    sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y phpmyadmin
fi

#----------------
# WordPress
#----------------
if [ '$INSTALL_WORDPRESS' = true ]; then
    echo Installing WordPress...
    echo Installing wp-cli...
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    sudo mv wp-cli.phar /usr/local/bin/wp

    echo Downloading Wordpress...
    sudo -u www-data wp core download --path=/var/www/html/

    echo Installing required php modules for WordPress...
    sudo apt-get -qq -y install php-mysql php-gd php-curl php-dom php-imagick php-mbstring php-zip php-intl

    echo Configuring WordPress...
    sudo mysql -Bse "CREATE USER IF NOT EXISTS wordpressuser@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON *.* TO 'wordpressuser'@'localhost';FLUSH PRIVILEGES;"
    sudo -u www-data wp config create --dbname=wordpress --dbuser=wordpressuser --dbpass=password --path=/var/www/html/
    wp db create --path=/var/www/html/
    sudo mysql -Bse "REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'wordpressuser'@'localhost';GRANT ALL PRIVILEGES ON wordpress.* TO wordpressuser@localhost;FLUSH PRIVILEGES;"
    sudo mkdir -p /var/www/html/wp-content/uploads
    sudo chmod 775 /var/www/html/wp-content/uploads
    sudo chown www-data:www-data /var/www/html/wp-content/uploads
    echo Increase max file upload size for PHP. Required for large media and backup imports
    sudo sed -i.bak -e "s/^upload_max_filesize.*/upload_max_filesize = 512M/g" /etc/php/*/apache2/php.ini
    sudo sed -i.bak -e "s/^post_max_size.*/post_max_size = 512M/g" /etc/php/*/apache2/php.ini
    sudo sed -i.bak -e "s/^max_execution_time.*/max_execution_time = 300/g" /etc/php/*/apache2/php.ini
    sudo sed -i.bak -e "s/^max_input_time.*/max_input_time = 300/g" /etc/php/*/apache2/php.ini
    sudo service apache2 restart
    sudo -u www-data wp core install --url=$(dig +short myip.opendns.com @resolver1.opendns.com) --title="Website Title" --admin_user="admin" --admin_password="password" --admin_email="x@y.com" --path=/var/www/html/
    sudo -u www-data wp plugin list --status=inactive --field=name --path=/var/www/html/ | xargs --replace=% sudo -u www-data wp plugin delete % --path=/var/www/html/
    sudo -u www-data wp theme list --status=inactive --field=name --path=/var/www/html/ | xargs --replace=% sudo -u www-data wp theme delete % --path=/var/www/html/
    sudo -u www-data wp plugin install all-in-one-wp-migration --activate --path=/var/www/html/
fi

#----------------
# Matomo Analytics
#----------------
if [ '$INSTALL_MATOMO' = true ]; then
    echo Installing Matomo Analytics Server
    sudo apt-get -qqy install unzip php-dom php-xml php-mbstring
    sudo service apache2 restart
    sudo wget https://builds.matomo.org/matomo.zip -P /var/www/html/
    sudo unzip -oq /var/www/html/matomo.zip -d /var/www/html/
    sudo chown -R www-data:www-data /var/www/html/matomo
    sudo rm -rf /var/www/html/matomo.zip
    sudo rm -rf /var/www/html/'How to install Matomo.html'
    sudo mysql -Bse "CREATE DATABASE matomodb;CREATE USER matomoadmin@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON matomodb.* TO matomoadmin@localhost; FLUSH PRIVILEGES;"
    sudo -u www-data wp plugin install matomo --activate --path=/var/www/html/
    sudo -u www-data wp plugin install wp-piwik --activate --path=/var/www/html/
    sudo -u www-data wp plugin install super-progressive-web-apps --activate --path=/var/www/html/
fi

###########################################
# Final Status Output
###########################################
if [ '$INSTALL_LAMP' = true ]; then
    printf "\nClick on this link to open your website: \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)\e[0m\n"
fi
if [ '$INSTALL_SFTP' = true ]; then
    printf "\nClick on this link to download WinSCP \e[3;4;33mhttps://dcus.short.gy/downloadWinSCP\e[0m - Note: User name = root and password = tester\n"
fi
if [ '$INSTALL_VSCODE' = true ]; then
    printf "\nSSH into your new VM (ssh vm) and run this command to open a VS Code tunnel:  \e[3;4;33msudo code tunnel\e[0m - Follow the instructions in the terminal to connect to VS code via the browser.\n"
    printf "\nYou can also access VS Code online version by visiting:  \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com):8080\e[0m \n"
fi
if [ '$INSTALL_DB' = true ]; then    
    printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/adminer/?username=admin\e[0m - You should see the Adminer Login page. Username is admin and password is password. Leave Database empty.\n"
    printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/phpmyadmin\e[0m - You should see the phpMyAdmin login page. admin/password\n"
fi
if [ '$INSTALL_WORDPRESS' = true ]; then
    printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)\e[0m - You should see the WordPress page.\n" &&
    printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/wp-admin\e[0m - You should see the WordPress Dashboard - admin/password\n"
fi
if [ '$INSTALL_MATOMO' = true ]; then
    printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/matomo\e[0m - You should see the Matomo Install page.\n"
fi
printf "\nYou can ssh into your new VM on this Cloud Shell using... \e[3;4;33mssh vm\e[0m\n"
echo ********************************
echo * SUCCESS! - Script completed! *
echo ********************************
'
