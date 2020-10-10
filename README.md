# secureserver
A tool to secure a Debian-based server. It takes out 30-60 minutes of sysadmin tasks.

## What does it do?
* Secures */etc/passwd* (makes sure there is only one root user)
* Secures *cron.d*
* Installs and configures *rkhunter*
* Installs and configures *UFW*
* Installs and configures *Clamav*
* Installs and configures *Fail2ban*
* Secures the *SSH* service
* Updates the system

## Usage
`sudo ./secureserver.sh <OPTION>`

## Options
* `-h, --help`: Output the help and exit
* `-q, --quiet`: Only output the neccessary things
