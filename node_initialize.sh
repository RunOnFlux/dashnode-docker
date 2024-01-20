#!/usr/bin/env bash
CONFIG_FILE="/root/.dashcore/dash.conf"
url_array=(
    "https://api4.my-ip.io/ip"
    "https://checkip.amazonaws.com"
    "https://api.ipify.org"
)
function get_ip() {
    for url in "$@"; do
        WANIP=$(curl --silent -m 15 "$url" | tr -dc '[:alnum:].')
        # Remove dots from the IP address
        IP_NO_DOTS=$(echo "$WANIP" | tr -d '.')
        # Check if the result is a valid number
        if [[ "$IP_NO_DOTS" != "" && "$IP_NO_DOTS" =~ ^[0-9]+$ ]]; then
            break
        fi
    done
}

if [[ ! -f $CONFIG_FILE ]]; then
    get_ip "${url_array[@]}"
    RPCUSER=$(pwgen -1 18 -n)
    PASSWORD=$(pwgen -1 20 -n)
    echo "rpcuser=$RPCUSER" >> $CONFIG_FILE
    echo "rpcpassword=$PASSWORD" >> $CONFIG_FILE
    echo "rpcallowip=127.0.0.1" >> $CONFIG_FILE
    echo "server=1" >> $CONFIG_FILE
    echo "daemon=1" >> $CONFIG_FILE
    echo "externalip=$WANIP" >> $CONFIG_FILE
    echo "maxconnections=256" >> $CONFIG_FILE
    if [[ "$KEY" != "" ]]; then 
      echo "masternodeblsprivkey=$KEY" >> $CONFIG_FILE
    fi
fi

[ -f /var/spool/cron/crontabs/root ] && crontab_check=$(cat /var/spool/cron/crontabs/root| grep -o utils | wc -l) || crontab_check=0
if [[ "$crontab_check" == "0" ]]; then
  echo -e " ADDED CRONE JOB FOR LOG CLEANER..."
  (crontab -l -u root 2>/dev/null; echo "* * * * * pidof dashd || /root/.dashcore/dashd") | crontab -
else
  echo -e " CRONE JOB ALREADY EXIST..."
fi

while true; do
 if [[ $(pgrep dashd) == "" ]]; then 
   echo -e "Starting daemon..."
   dashd -daemon
 fi
 sleep 120
done
