#!/bin/bash

provider=$1
first_router=$2
last_router=$3

for i in $(seq "$first_router" "$last_router"); do
    if [[ $i -lt 10 ]]; then
        rid="p${provider}r${i}v"
        echo "Pinging cloudflare.com from VyOS $rid"
        ssh -o StrictHostKeyChecking=no "$rid" "ping -c 2 cloudflare.com"
        echo "------------------------------------------------------------------------------------------------------------------------"
    else
        rid="p${provider}r${i}m"
        MIKROTIK_IP="10.20.30.1${i}"
        echo "Pinging cloudflare.com from MikroTik $rid "
        ssh -o StrictHostKeyChecking=no admin@"$MIKROTIK_IP" <<EOF
ping cloudflare.com count=2
EOF
        echo "------------------------------------------------------------------------------------------------------------------------"      
    fi
done

    

