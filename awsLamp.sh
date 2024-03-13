# This script is designed to be run in AWS CloudShell. Here are two bash differnet commands to run this script:
# bash <(curl -sL tinyurl.com/awsLamp)
# bash <(curl -sL https://raw.githubusercontent.com/danielcregg/aws-cli-lamp-script/main/awsLamp.sh)
echo Cleaning up old resources...
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
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
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

echo Creating new security group...
SG_ID=$(aws ec2 create-security-group \
    --group-name webServerSecurityGroup \
    --description "Web Server security group" \
    --output text)

echo Opening required ports i.e. SSH, HTTP, HTTPS and RDP...
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3389 --cidr 0.0.0.0/0 > /dev/null

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

AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server*' \
              'Name=state,Values=available' \
              'Name=virtualization-type,Values=hvm' \
              'Name=architecture,Values=x86_64' \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
    
echo Creating instance...
INSTANCE_ID=$(aws ec2 run-instances \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=myWebServerAuto}]" \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.medium \
    --key-name key_WebServerAuto \
    --security-group-ids $SG_ID \
    --output text \
    --query 'Instances[0].InstanceId' \
    --block-device-mappings DeviceName=/dev/sda1,Ebs="{VolumeSize=15,VolumeType=gp2}")

echo Waiting for the new instance to enter a running state...
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID

echo Allocating a new Elastic IP...
ELASTIC_IP=$(aws ec2 allocate-address \
    --domain vpc \
    --query 'PublicIp' \
    --output text)

# Get the allocation ID of the Elastic IP
ELASTIC_IP_ALLOCATION_ID=$(aws ec2 describe-addresses \
    --public-ips $ELASTIC_IP \
    --query 'Addresses[0].AllocationId' \
    --output text)

echo Adding a Name to the Elastic IP
aws ec2 create-tags \
    --resources $ELASTIC_IP_ALLOCATION_ID \
    --tags Key=Name,Value=elasticIPWebServerAuto

echo Associating the new Elastic IP with the new instance...
aws ec2 associate-address \
    --instance-id $INSTANCE_ID \
    --public-ip $ELASTIC_IP > /dev/null

echo "Host ws
    HostName $ELASTIC_IP
    User ubuntu
    IdentityFile ~/.ssh/key_WebServerAuto" > ~/.ssh/config
    
echo Trying to SSH into new instance...please hold...
sleep 15
ssh -o StrictHostKeyChecking=no -i ~/.ssh/key_WebServerAuto ubuntu@$ELASTIC_IP \
'\
echo "Successfully SSHed into new instance..." &&

echo "Updating apt repos..." &&
sudo apt update &&

echo Installing LAMP... &&
sudo apt -f -y install apache2 mysql-server php &&

echo Configuring LAMP... &&
sudo sed -i.bak -e "s/DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" /etc/apache2/mods-enabled/dir.conf &&
sudo wget https://raw.githubusercontent.com/danielcregg/simple-php-website/main/index.php -P /var/www/html/ &&
sudo rm -rf /var/www/html/index.html &&
sudo systemctl restart apache2

echo "Enabling root login for SFTP..." &&
sudo sed -i "/PermitRootLogin/c\PermitRootLogin yes" /etc/ssh/sshd_config &&
sudo echo -e "tester\ntester" | sudo passwd root &&
sudo systemctl restart sshd &&

echo "Enable Vscode tunnel login via browser..." && 
sudo wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg &&
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/ &&
sudo sh -c "echo 'deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main' > /etc/apt/sources.list.d/vscode.list" &&
sudo apt update -qqq > /dev/null &&
sudo apt install code -qq -y 2>/dev/null &&
code --install-extension ms-vscode.remote-server 2>/dev/null &&
#sudo code tunnel service install
#sudo code tunnel --no-sleep

echo Installing Adminer silently... &&
sudo DEBIAN_FRONTEND=noninteractive apt-get install -qqq -y adminer 2>/dev/null &&
echo Configuring Andminer &&
sudo a2enconf adminer && 
sudo systemctl reload apache2 &&
sudo mysql -Bse "CREATE USER IF NOT EXISTS admin@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON *.* TO admin@localhost;FLUSH PRIVILEGES;" &&

echo Install phpmyadmin silently... &&
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" &&
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true" &&
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password 'password'" &&
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password 'password'" &&
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/internal/skip-preseed boolean true" &&
sudo DEBIAN_FRONTEND=noninteractive apt install -qq -y phpmyadmin &&

echo Installing WordPress... &&
echo Installing wp-cli... &&
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar &&
chmod +x wp-cli.phar &&
sudo mv wp-cli.phar /usr/local/bin/wp &&

echo Downloading Wordpress... &&
sudo -u www-data wp core download --path=/var/www/html &&

echo Installing required php modules for WordPress... &&
sudo apt -qq -y install php-mysql php-gd php-curl php-dom php-imagick php-mbstring php-zip php-intl &&

echo Configuring WordPress...&&
sudo mysql -Bse "CREATE USER IF NOT EXISTS wordpressuser@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON *.* TO 'wordpressuser'@'localhost';FLUSH PRIVILEGES;" &&
sudo -u www-data wp config create --dbname=wordpress --dbuser=wordpressuser --dbpass=password --path=/var/www/html/ &&
wp db create --path=/var/www/html/
sudo mkdir -p /var/www/html/wp-content/uploads &&
sudo chown -R www-data:www-data /var/www &&
sudo -u www-data wp config set FS_METHOD direct --raw --type=constant --path=/var/www/html/
echo Increase max file upload size for PHP. Required for large media and backup imports &&
sudo sed -i.bak -e 's/^upload_max_filesize.*/upload_max_filesize = 512M/g' /etc/php/*/apache2/php.ini &&
sudo sed -i.bak -e 's/^post_max_size.*/post_max_size = 512M/g' /etc/php/*/apache2/php.ini &&
sudo sed -i.bak -e 's/^max_execution_time.*/max_execution_time = 300/g' /etc/php/*/apache2/php.ini &&
sudo sed -i.bak -e 's/^max_input_time.*/max_input_time = 300/g' /etc/php/*/apache2/php.ini &&
sudo service apache2 restart &&
sudo -u www-data wp core install --url=$(dig +short myip.opendns.com @resolver1.opendns.com) --title='Website Title' --admin_user='admin' --admin_password='password' --admin_email='x@y.com' --path=/var/www/html/ &&
wp plugin list --status=inactive --field=name --allow-root | xargs --replace=% sudo -u www-data wp plugin delete % --allow-root &&
wp theme list --status=inactive --field=name --allow-root | xargs --replace=% sudo -u www-data wp theme delete % --allow-root &&
sudo -u www-data wp plugin install all-in-one-wp-migration --activate &&

#echo Installing Matomo Analytics Server &&
#sudo apt -y install php-dom php-dom php-xml php-simplexml &&
#sudo apt -y install unzip php-mbstring;sudo service apache2 restart &&
#sudo wget https://builds.matomo.org/matomo.zip -P ~;sudo apt -y install unzip;sudo unzip -oq ~/matomo.zip -d /var/www/html &&
#sudo chown -R www-data:www-data /var/www/html/matomo;sudo chmod -R 0755 /var/www/html/matomo/tmp &&
#sudo mysql -Bse "CREATE DATABASE matomodb;CREATE USER matomoadmin@localhost IDENTIFIED BY \"password\";GRANT ALL PRIVILEGES ON matomodb.* TO matomoadmin@localhost; FLUSH PRIVILEGES;" &&
#sudo -u www-data wp plugin install matomo --activate &&
##sudo -u www-data wp plugin install wp-piwik --activate &&

printf "\nClick on this link to open the default Apache webpage: \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)\e[0m\n"
printf "\nClick on this link to download WinSCP \e[3;4;33mhttps://dcus.short.gy/downloadWinSCP\e[0m - Note: User name = root and password = tester\n"
printf "\nSSH into your new VM  and run this command to open a VS Code tunnel:  \e[3;4;33msudo code tunnel service install;sudo code tunnel --no-sleep\e[0m - Follow the instructions in the terminal to connect to VS code via the browser.\n"
printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/adminer/?username=admin\e[0m - You should see the Adminer Login page. Username is admin and password is password. Leave Database empty.\n"
printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/phpmyadmin\e[0m - You should see the phpMyAdmin login page. admin/password\n"
printf "\nYou can log into your new VM using... \e[3;4;33mssh ws\e[0m\n"
#printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)\e[0m - You should see the WordPress page.\n" &&
#printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/wp-admin\e[0m - You should see the WordPress Dashboard - admin/password\n"
#printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/matomo\e[0m - You should see the Matomo Install page.\n"
echo ********************************
echo * SUCCESS! - Script completed! *
echo ********************************
'
