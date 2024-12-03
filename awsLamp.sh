#!/bin/bash

# This script is designed to be run in AWS CloudShell. Here are two bash differnet commands to run this script:
# bash <(curl -sL tinyurl.com/awsLamp)
# bash <(curl -sL https://raw.githubusercontent.com/danielcregg/aws-cli-lamp-script/main/awsLamp.sh)
# for the latest builds run below
# bash <(curl -sL https://raw.githubusercontent.com/danielcregg/aws-cli-lamp-script/dev-branch/awsLamp.sh)

# The following variables are used to determine what to install
INSTALL_LAMP=false
INSTALL_SFTP=false
INSTALL_VSCODE=false
INSTALL_DB=false
INSTALL_WORDPRESS=false
INSTALL_MATOMO=false

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

printf "\e[3;4;31mCleaning up old resources...\e[0m\n"
# Get the allocation IDs of the Elastic IPs with the tag name "WebServerPublicIPAuto"
EXISTING_ELASTIC_IP_ALLOCATION_IDS=$(aws ec2 describe-tags \
    --filters "Name=key,Values=Name" "Name=value,Values=elasticIPWebServerAuto" "Name=resource-type,Values=elastic-ip" \
    --query 'Tags[*].ResourceId' \
    --output text)

# If there are any Elastic IPs with the tag name "WebServerPublicIPAuto", release them
for ALLOCATION_ID in $EXISTING_ELASTIC_IP_ALLOCATION_IDS
do
  aws ec2 release-address --allocation-id $ALLOCATION_ID
done

# Get the IDs of the instances with the name "myWebServerAuto"
EXISTING_INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=myWebServerAuto" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

# If there are any running instances with the name "myWebServerAuto", terminate them
if [ "$EXISTING_INSTANCE_IDS" != "" ]; then
  aws ec2 terminate-instances --instance-ids $EXISTING_INSTANCE_IDS > /dev/null
  # Waiting for instance to be terminated...
  aws ec2 wait instance-terminated --instance-ids $EXISTING_INSTANCE_IDS
fi

# Get the ID of the security group if it exists
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
    --group-names webServerSecurityGroup \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

# If the security group exists, delete it
if [ "$EXISTING_SG_ID" != "" ]; then
  aws ec2 delete-security-group --group-id $EXISTING_SG_ID
fi

# Check if a key pair exists and if so delete it
if aws ec2 describe-key-pairs --key-name key_WebServerAuto >/dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name key_WebServerAuto > /dev/null
  sudo test -f ~/.ssh/key_WebServerAuto && sudo rm -rf ~/.ssh/key_WebServerAuto* ~/.ssh/known_host* ~/.ssh/config
fi

echo "Creating new security group..."
SG_ID=$(aws ec2 create-security-group \
    --group-name webServerSecurityGroup \
    --description "Web Server security group" \
    --query 'GroupId' \
    --output text)

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

echo Creating new key pair...
mkdir -p ~/.ssh
aws ec2 create-key-pair \
    --key-name key_WebServerAuto \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/key_WebServerAuto  
chmod 600 ~/.ssh/key_WebServerAuto

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
while true; do
    STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    printf "\rCurrent state: %-10s" "$STATE"
    
    if [ "$STATE" = "running" ]; then
        echo -e "\nInstance is ready!"
        # Wait a bit more for the OS to fully boot
        echo "Waiting 30 seconds for system initialization..."
        for i in {30..1}; do
            printf "\rTime remaining: %2d seconds" "$i"
            sleep 1
        done
        echo -e "\nSystem should be ready now"
        break
    elif [ "$STATE" = "terminated" ] || [ "$STATE" = "shutting-down" ]; then
        echo -e "\nError: Instance terminated unexpectedly"
        exit 1
    fi
    
    sleep 2
done

# Replace the Elastic IP section with this updated code:
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
MAX_RETRIES=3
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

ssh -o StrictHostKeyChecking=no -i ~/.ssh/key_WebServerAuto ubuntu@$ELASTIC_IP \
'\
set -e
echo "Successfully SSHed into new instance..."

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

if [ '$INSTALL_SFTP' = true ]; then
    echo Enabling root login for SFTP...
    sudo sed -i "/PermitRootLogin/c\PermitRootLogin yes" /etc/ssh/sshd_config
    sudo echo -e "tester\ntester" | sudo passwd root
    sudo systemctl restart sshd
fi

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

# Install DB tools if requested
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

# Install WordPress if requested
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

# Install Matomo if requested
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
