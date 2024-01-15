echo Cleaning up old resources...
# Get the allocation IDs of the Elastic IPs with the tag name "WebServerPublicIPAuto"
EXISTING_ELASTIC_IP_ALLOCATION_IDS=$(aws ec2 describe-tags --filters "Name=key,Values=Name" "Name=value,Values=elasticIPWebServerAuto" "Name=resource-type,Values=elastic-ip" --query 'Tags[*].ResourceId' --output text)

# If there are any Elastic IPs with the tag name "WebServerPublicIPAuto", release them
for ALLOCATION_ID in $EXISTING_ELASTIC_IP_ALLOCATION_IDS
do
  aws ec2 release-address --allocation-id $ALLOCATION_ID
done

# Get the IDs of the instances with the name "myWebServerAuto"
EXISTING_INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=myWebServerAuto" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].InstanceId' --output text)

# If there are any running instances with the name "myWebServerAuto", terminate them
if [ "$EXISTING_INSTANCE_IDS" != "" ]; then
  aws ec2 terminate-instances --instance-ids $EXISTING_INSTANCE_IDS > /dev/null
  # Waiting for instance to be terminated...
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
fi

# Get the ID of the security group if it exists
EXISTING_SG_ID=$(aws ec2 describe-security-groups --group-names webServerSecurityGroup --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

# If the security group exists, delete it
if [ "$EXISTING_SG_ID" != "" ]; then
  aws ec2 delete-security-group --group-id $EXISTING_SG_ID
fi

# Check if the key pair exists
if aws ec2 describe-key-pairs --key-name webServerKey >/dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name webServerKey > /dev/null
  rm WebServerKey.pem
fi

echo Creating new security group...
# Create a new security group and get its ID
SG_ID=$(aws ec2 create-security-group --group-name webServerSecurityGroup --description "Web Server security group" --output text)

echo Adding new rules to the security group...
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3389 --cidr 0.0.0.0/0 > /dev/null

echo Creating new key pair...
# Create a new key pair
aws ec2 create-key-pair --key-name webServerKey --query 'KeyMaterial' --output text > WebServerKey.pem
chmod 600 WebServerKey.pem

echo Creating a new EC2 instance...
INSTANCE_ID=$(aws ec2 run-instances --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=myWebServerAuto}]" --image-id ami-0c7217cdde317cfec --count 1 --instance-type t2.medium --key-name webServerKey --security-group-ids $SG_ID --output text --query 'Instances[0].InstanceId' --block-device-mappings DeviceName=/dev/sda1,Ebs="{VolumeSize=15,VolumeType=gp2}")

echo Waiting for the new instance to enter a running state...
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

echo Allocating a new Elastic IP...
ELASTIC_IP=$(aws ec2 allocate-address --domain vpc --query 'PublicIp' --output text)

# Get the allocation ID of the Elastic IP
ELASTIC_IP_ALLOCATION_ID=$(aws ec2 describe-addresses --public-ips $ELASTIC_IP --query 'Addresses[0].AllocationId' --output text)

echo Adding a Name to the Elastic IP
aws ec2 create-tags --resources $ELASTIC_IP_ALLOCATION_ID --tags Key=Name,Value=elasticIPWebServerAuto

echo Associating the new Elastic IP with the new instance...
aws ec2 associate-address --instance-id $INSTANCE_ID --public-ip $ELASTIC_IP > /dev/null

echo Installing LAMP on the new instance...
# SSH into instance
ssh -i WebServerKey.pem -o StrictHostKeyChecking=no ubuntu@$ELASTIC_IP \
'\
echo Updating package repository... &&
sudo apt-get update -qq && 
echo Installing apache, mysql and php... &&
sudo apt install apache2 mysql-server php -y &&
echo Configuring LAMP server... &&
sudo sed -i.bak -e "s/DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm/DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm/g" /etc/apache2/mods-enabled/dir.conf &&
sudo touch /var/www/html/info.php;sudo chmod 666 /var/www/html/info.php;sudo echo "<?php phpinfo(); ?>" > /var/www/html/info.php &&
printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)\e[0m - You should see the Apache default page.\n"
printf "\nOpen an internet browser (e.g. Chrome) and go to \e[3;4;33mhttp://$(dig +short myip.opendns.com @resolver1.opendns.com)/info.php\e[0m - You should see a PHP info page.\n"
'
