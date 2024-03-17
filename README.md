# AWS LAMP Stack Setup Script  

## Usage  

This is an bash script which incorporates AWS CLI commands to create an ubuntu based LAMP server on AWS. This script is meant to be run in AWS CloudShell. Here are the steps to run this script:

1. Log into your AWS Dashboard
2. Open the CloudShell and wait for it to load
3. Issue this bash command:

```bash
bash <(curl -sL tinyurl.com/awsLamp)
```

This script should take about 5 minutes to complete.

Optional flags: -lamp -sftp -vscode -db -wp -mt

### Post-Installation Instructions

After running the script, follow these instructions based on the software you chose to install:

- **WinSCP**: Click on [this link](https://dcus.short.gy/downloadWinSCP) to download WinSCP. Use 'root' as the username and 'tester' as the password.

- **VS Code**: SSH into your new VM using the command `ssh vm`. Then run the command `sudo code tunnel` to open a VS Code tunnel. Follow the instructions in the terminal to connect to VS Code via the browser.

- **Database**: Open a browser and go to `http://<your-ip>/adminer/?username=admin` to see the Adminer Login page. The username is 'admin' and the password is 'password'. You can update the password to your liking. Leave the Database field empty. Alternatively, you can go to `http://<your-ip>/phpmyadmin` to see the phpMyAdmin login page. The credentials are 'admin'/'password'.

- **WordPress**: Open a browser and go to `http://<your-ip>` to see the WordPress page. To access the WordPress Dashboard, go to `http://<your-ip>/wp-admin`. The credentials are 'admin'/'password'.

