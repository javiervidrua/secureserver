#!/usr/bin/env bash

# MIT License

# Copyright (c) 2020 Javier Vidal Ruano

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# =========================================================================== #
# = VARIABLES =============================================================== #
# =========================================================================== #
SCRIPT_NAME='secureserver.sh'

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`
#echo "${red}red text ${green}green text${reset}"

# Reset Bash time counter
SECONDS=0

# Argument variables (defaults)
QUIET=0

# =========================================================================== #
# = FUNCTIONS =============================================================== #
# =========================================================================== #
function checkArguments(){
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -q|--quiet)
                QUIET=1
                shift # Move on to the next option
                ;;
            *)
                echo "${red}[-] Unknown option: $1${reset}"
                echo "[*] Try ""'""$SCRIPT_NAME --help""'"" for more information"
                exit 1
                ;;
        esac
    done
}

function checkFileReadable(){
    [ -r "${1}" ]
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: ${1} file is not readable${reset}"
        return 1
    fi
}

function checkRoot(){
    if [ "$(id -u)" != "0" ]; then
        echo "${red}[-] Error: You must be root to run this script${reset}"
        usage
        exit 1
    fi
}

function configureClamav(){
    [ $QUIET -eq 1 ] || echo '[*] Installing clamav'
    apt install clamav -y clamav-daemon -y
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not install clamav${reset}"
        return 1
    fi
    systemctl stop clamav-freshclam
    freshclam
    systemctl start clamav-daemon
    systemctl start clamav-freshclam
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not start clamav${reset}"
        return 1
    fi

    [ $QUIET -eq 1 ] || echo '[*] Clamav configured'
    return 0
}

function configureFail2ban(){
    [ $QUIET -eq 1 ] || echo '[*] Configuring fail2ban'
    if [ -e /etc/fail2ban/jail.local ]; then
        createBackup /etc/fail2ban/jail.local
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    echo '[DEFAULT]
bantime  = 30m
findtime  = 60
maxretry  = 30' > /etc/fail2ban/jail.local
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not configure fail2ban${reset}"
        return 2
    fi
    service fail2ban restart
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not restart fail2ban${reset}"
        return 2
    fi

    [ $QUIET -eq 1 ] || echo '[*] Fail2ban configured'
    return 0
}

function configureRootkitHunter(){
    [ $QUIET -eq 1 ] || echo '[*] Installing rkhunter'
    apt install rkhunter -y
    # create the cronjob to analyse the system each day 
    [ $QUIET -eq 1 ] || echo '[*] Creating rkhunter cronjob'
    echo '
#!/bin/bash
OUTPUT=`rkhunter --check --cronjob --report-warnings-only --nocolors --skip-keypress`
if [ "$OUTPUT" != "" ]
then
    echo $OUTPUT | mail -s "[rkhunter] Warnings found for $(hostname)" root@localhost.localdomain
fi' > /etc/cron.daily/rkhunter_check && chmod 755 /etc/cron.daily/rkhunter_check

    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not create cronjob for rkhunter${reset}"
        return 1
    fi

    createBackup /etc/rkhunter.conf

    [ $QUIET -eq 1 ] || echo '[*] Configuring /etc/rkhunter.conf'
    # Leave WEB_CMD directive empty
    searchAndReplace "WEB_CMD=\"/bin/false\"" "WEB_CMD=\"\"" /etc/rkhunter.conf
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not configure rkhunter (/etc/rkhunter.conf)${reset}"
        return 2
    fi

    [ $QUIET -eq 1 ] || echo '[*] Rkhunter configured'
    return 0
}

function configureUfw(){
    [ $QUIET -eq 1 ] || echo '[*] Installing ufw'
    apt install ufw -y
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not install ufw${reset}"
        return 1
    fi
    [ $QUIET -eq 1 ] || echo '[*] Enabling ufw'
    ufw enable
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not enable ufw${reset}"
        return 1
    fi
    [ $QUIET -eq 1 ] || echo '[*] Allowing common services through ufw'
    function allowUfw(){
        ufw allow ${1}
    }
    ufw allow ftp ssh smtp http pop3 imap https
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not allow common services through ufw${reset}"
        return 1
    fi
    ufw logging on
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not allow common services through ufw${red}"
        return 1
    fi

    [ $QUIET -eq 1 ] || echo '[*] Ufw configured'
    return 0
}

function createBackup(){
    [ $QUIET -eq 1 ] || echo "[*] Creating backup of ${1}"
    cp ${1} ${1}.old
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not create a backup of ${1}${reset}"
        return 1
    fi
    [ $QUIET -eq 1 ] || echo "[*] Backup of ${1} created"
    return 0
}

function main(){
    if [ $QUIET -eq 1 ]; then
        echo "[*] Quiet mode"
    fi

    secureCronDirectory
    if [ $? -ne 0 ]; then
        exit 1
    fi

    securePasswdFile && rm -rf /etc/passwd.old
    if [ $? -ne 0 ]; then
        if [ $? -eq 1 ]; then
            restoreBackup /etc/passwd
        fi
        exit 1
    fi

    secureSSHservice && rm -rf /etc/ssh/sshd_config.old
    if [ $? -ne 0 ]; then
        if [ $? -eq 2 ]; then
            restoreBackup /etc/ssh/sshd_config
        fi
        exit 1
    fi

    secureSSHdirectory
    if [ $? -ne 0 ]; then
        exit 1
    fi

    configureRootkitHunter && rm -rf /etc/rkhunter.conf.old
    if [ $? -ne 0 ]; then
        if [ $? -eq 2 ]; then
            restoreBackup /etc/rkhunter.conf
        fi
        exit 1
    fi

    configureUfw
    if [ $? -ne 0 ]; then
        exit 1
    fi

    configureClamav
    if [ $? -ne 0 ]; then
        exit 1
    fi

    configureFail2ban && rm -rf /etc/fail2ban/jail.local.old
    if [ $? -ne 0 ]; then
        if [ $? -eq 2 ]; then
            restoreBackup /etc/fail2ban/jail.local
        fi
        exit 1
    fi

    updateSystem
    if [ $? -ne 0 ]; then
        exit 1
    fi

    return 0
}

function searchAndReplace(){
    COUNTER=$(grep -E "*$1*" "$3" -n | cut -d: -f1)
    if [[ -z $(grep -E "*$1*" "$3" -n | cut -d: -f1) ]]; then
        return 1
    elif [[ $(grep -E "*$1*" "$3" -n | cut -d: -f1 | wc -l) -gt 1 ]]; then
        return 2
    fi
    TO_SED="$COUNTER""s/.*/""$2""/"
    sed -i "$TO_SED" $3

    return 0
}

function secureCronDirectory(){
    [ $QUIET -eq 1 ] || echo '[*] Securing /etc/cron.d'
    chown root:root /etc/cron.d
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not secure /etc/cron.d${reset}"
        return 1
    fi
    chmod og-rwx /etc/cron.d
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not secure /etc/cron.d${reset}"
        return 1
    fi

    [ $QUIET -eq 1 ] || echo '[*] /etc/cron.d secured'
    return 0
}

function securePasswdFile(){ # check /etc/passwd to look for anything strange and fix it
    checkFileReadable /etc/passwd || exit 1
    createBackup /etc/passwd
    if [ $? -ne 0 ]; then
        return 1
    fi
    [ $QUIET -eq 1 ] || echo '[*] Securing /etc/passwd'
    
    NUMBER_OF_ROOT_USERS=$(grep -E '[a-zA-Z]:?:0:*' /etc/passwd | cut -d: -f3 | wc -l)
    if [ $NUMBER_OF_ROOT_USERS == '0' ]; then
        echo '[*] This system does not have a root user! How did you run this script?!?'
    elif [ $NUMBER_OF_ROOT_USERS == '1' ]; then
        [ $QUIET -eq 1 ] || echo '[*] /etc/passwd looks good'
    elif [ $NUMBER_OF_ROOT_USERS != '1' ]; then
        echo '[*] Found more users with UID=0 than root!'
        while read LINE; do
            # If the UID is 0
            if [ $(echo $LINE | cut -d: -f3) == '0' ]; then
                BAD_USER=$(echo $LINE | cut -d: -f1)
                if [ $BAD_USER != 'root' ]; then
                    echo "[*] Locking account for user ${BAD_USER}"
                    passwd -l ${BAD_USER}
                    if [ $? -ne 0 ]; then
                        echo "${red}[-] Could not lock the account of the user ${BAD_USER}${reset}"
                        return 2
                    fi
                    [ $QUIET -eq 1 ] || echo "[*] Account for user ${BAD_USER} locked"
                fi
            fi
            # If the GUID is 0
            if [ $(echo $LINE | cut -d: -f4) == '0' ]; then
                BAD_USER=$(echo $LINE | cut -d: -f1)
                if [ $BAD_USER != 'root' ]; then
                    echo "[*] Locking account for user ${BAD_USER}"
                    passwd -l ${BAD_USER}
                    if [ $? -ne 0 ]; then
                        echo "${red}[-] Could not lock the account of the user ${BAD_USER}${reset}"
                        return 3
                    fi
                    [ $QUIET -eq 1 ] || echo "[*] Account for user ${BAD_USER} locked"
                fi
            fi
        done < /etc/passwd
    fi

    [ $QUIET -eq 1 ] || echo '[*] /etc/passwd secured'
    return 0
}

function secureSSHservice(){
    checkFileReadable /etc/ssh/sshd_config || exit 1
    createBackup /etc/ssh/sshd_config
    if [ $? -ne 0 ]; then
        return 1
    fi

    [ $QUIET -eq 1 ] || echo "[*] Securing SSH service"
    searchAndReplace "LoginGraceTime" "LoginGraceTime 15" /etc/ssh/sshd_config && \
    searchAndReplace "MaxAuthTries" "MaxAuthTries 3" /etc/ssh/sshd_config && \
    searchAndReplace "MaxStartups" "MaxStartups 10:30:100" /etc/ssh/sshd_config && \
    searchAndReplace "MaxSessions" "MaxSessions 3" /etc/ssh/sshd_config && \
    searchAndReplace "PermitRootLogin no" "PermitRootLogin no" /etc/ssh/sshd_config && \
    echo 'Protocol 2' >> /etc/ssh/sshd_config
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not configure SSH${reset}"
        return 2
    fi
    service ssh restart
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not restart the SSH service${reset}"
        return 3
    fi

    [ $QUIET -eq 1 ] || echo "[*] SSH service secured"
    return 0
}

function secureSSHdirectory(){
    [ $QUIET -eq 1 ] || echo "[*] Securing SSH directory"
    SSH_DIR='/root/.ssh'
    checkFileReadable ${SSH_DIR}
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: ${SSH_DIR} not readable${reset}"
        return 1
    fi
    
    chown root:root -R $SSH_DIR && \
    chmod 700 $SSH_DIR
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not secure ${SSH_DIR}${reset}"
        return 2
    fi 

    if [ checkFileReadable "${SSH_DIR}/authorized_keys" ]; then
        [ $QUIET -eq 1 ] || echo "[*] Securing ${SSH_DIR}/authorized_keys"
        chmod 400 $SSH_DIR/authorized_keys && \
        chattr +i $SSH_DIR/authorized_keys
        if [ $? -ne 0 ]; then
            echo "${red}[-] Error: Could not secure ${SSH_DIR}/authorized_keys${reset}"
            return 3
        fi
    fi

    [ $QUIET -eq 1 ] || echo "[*] SSH directory secured"
    return 0
}

function restoreBackup(){
    [ $QUIET -eq 1 ] || echo "[*] Restoring backup of ${1}"
    mv ${1}.old ${1}
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not restore the backup of ${1}${reset}"
        return 1
    fi
    [ $QUIET -eq 1 ] || echo "[*] Backup of ${1} restored"
    return 0
}

function updateSystem(){
    apt update && apt upgrade -y && apt autoremove -y && apt autoclean -y
    if [ $? -ne 0 ]; then
        echo "${red}[-] Error: Could not update the system${reset}"
    fi
}

function usage() {
    echo "[*] Usage: sudo ./$SCRIPT_NAME"
    echo "      -h,  --help     Output this help and exit"
    echo "      -q,  --quiet    Only output the neccesary things"
    echo ""
    echo "[*] Example: sudo ./$SCRIPT_NAME --quiet"
}

# =========================================================================== #
# = MAIN ==================================================================== #
# =========================================================================== #
checkArguments $@
checkRoot
main
ELAPSED_TIME="[*] Elapsed time: $(($SECONDS / 3600))hrs $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
[ $QUIET -eq 1 ] || echo $ELAPSED_TIME
