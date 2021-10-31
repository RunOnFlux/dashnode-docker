#!/usr/bin/env bash

function get_ip() {

    WANIP=$(curl --silent -m 15 https://api4.my-ip.io/ip | tr -dc '[:alnum:].')

    if [[ "$WANIP" == "" ]]; then
      WANIP=$(curl --silent -m 15 https://checkip.amazonaws.com | tr -dc '[:alnum:].')
    fi

    if [[ "$WANIP" == "" ]]; then
      WANIP=$(curl --silent -m 15 https://api.ipify.org | tr -dc '[:alnum:].')
    fi
}


get_ip
RPCUSER=$(pwgen -1 8 -n)
PASSWORD=$(pwgen -1 20 -n)

if [[ -f /root/.dashcore/dash.conf ]]; then
  rm  /root/.dashcore/dash.conf
fi

touch /root/.dashcore/dash.conf
cat << EOF > /root/.dashcore/dash.conf
rpcuser=$RPCUSER
rpcpassword=$PASSWORD
rpcallowip=127.0.0.1
server=1
daemon=1
externalip=$WANIP
masternodeblsprivkey=$KEY
maxconnections=256
EOF

while true; do
dashd -daemon
sleep 60
done
