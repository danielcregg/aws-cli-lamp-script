# AWS LAMP Stack Automated Deployment Script

## Overview
This bash script automates the deployment of a complete LAMP stack environment on AWS using the AWS CLI. It's designed to run in the AWS CloudShell or any bash terminal with AWS CLI installed. It provides a modular installation approach with various optional components.

## Quick Start
1. Log into your AWS Management Console
2. Open AWS CloudShell
3. Run the command below in the AWS CloudShell terminal:

```bash
bash <(curl -sL tinyurl.com/awsLamp)
```
**NOTE**
- If you run the script above with no flags it creates a clean Ubuntu instance on your AWS account under EC2. 
- If you add the optional flags below it installs the associated software.
- This script should take about 3 minutes to complete if all software is installed. 

## Optional Installation flags

Choose your installation type using one of these flags:

| Flag | Components Installed | Description |
|------|---------------------|-------------|
| `-lamp` | • LAMP Stack (Base) | Basic LAMP server setup with Apache, MySQL, and PHP |
| `-sftp` | • LAMP Stack<br>• SFTP Access | Adds root SFTP access with password authentication |
| `-vscode` | • LAMP Stack<br>• SFTP Access<br>• VS Code Server | Adds browser-based code editor with port 8080 access |
| `-db` | • LAMP Stack<br>• SFTP Access<br>• VS Code Server<br>• Adminer<br>• phpMyAdmin | Adds web-based database management tools |
| `-wp` | • LAMP Stack<br>• SFTP Access<br>• VS Code Server<br>• Adminer<br>• phpMyAdmin<br>• WordPress | Adds WordPress with optimized settings |
| `-mt` | • LAMP Stack<br>• SFTP Access<br>• VS Code Server<br>• Adminer<br>• phpMyAdmin<br>• WordPress<br>• Matomo | Adds Matomo analytics platform |

Example usage:
```bash
bash <(curl -sL tinyurl.com/awsLamp) -mt
```
The above command would create an Ubuntu server with everything installed (i.e. LAMP Stack, SFTP Access, VS Code Server, Adminer, phpMyAdmin, WordPress, Matomo)

## Features
- **Base Installation**
  - Ubuntu Server 22.04 LTS

- **Optional Components**
  - LAMP
  - SFTP Access with root login
  - VS Code Server for browser-based development
  - Database Management Tools (Adminer & phpMyAdmin)
  - WordPress CMS with optimized settings
  - Matomo Analytics

### Post-Installation Instructions

After running the script, follow these instructions based on the software you chose to install:

- **WinSCP**: Click on [this link](https://dcus.short.gy/downloadWinSCP) to download WinSCP. Use 'root' as the username and 'tester' as the password.

- **VS Code**: SSH into your new VM using the command `ssh vm`. Then run the command `sudo code tunnel` to open a VS Code tunnel. Follow the instructions in the terminal to connect to VS Code via the browser.

- **Database**: Open a browser and go to `http://<your-ip>/adminer/?username=admin` to see the Adminer Login page. The username is 'admin' and the password is 'password'. You can update the password to your liking. Leave the Database field empty. Alternatively, you can go to `http://<your-ip>/phpmyadmin` to see the phpMyAdmin login page. The credentials are 'admin'/'password'.

- **WordPress**: Open a browser and go to `http://<your-ip>` to see the WordPress page. To access the WordPress Dashboard, go to `http://<your-ip>/wp-admin`. The credentials are 'admin'/'password'.

