# secureserver
A tool to secure a Debian-based server.

## What does it do?
* Secures the passwd file (only one root user)
* Secures cron.d
* Installs and configures rkhunter
* Installs and configures UFW
* Installs and configures Clamav
* Installs and configures Fail2ban
* Secures the SSH service
* Updates the system

## Usage
`sudo ./secureserver.sh <OPTION>`

## Options
* `-h, --help`: Output the help and exit
* `-q, --quit`: Only output the neccessary things
