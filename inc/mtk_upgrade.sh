#!/bin/bash

provider=$1
first_router=$2
last_router=$3

if [[ $# -ne 3 ]]; then
    echo -e "${R}Error: At least one variable empty!${NC}"
    exit 1
fi

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

# Start
echo -e "${C}Starting router$([[ $first_router != $last_router ]] && echo s), if not running. Waiting ...${NC}"
sudo  bash ${HOME}/inc/general/start.sh $provider $first_router $last_router 4

# Upgrade MikroTik
for r in $(seq $first_router $last_router); do
    echo -e "${C}Upgrading router p${provider}r${r}m (if neccessary).${NC}"
    MIKROTIK_IP="10.20.30.1$r"
    ssh admin@$MIKROTIK_IP << EOF   
    /system package update check-for-updates
    :delay 5
    /system package update download
    :delay 10
    /system package update install
    :delay 5
    /system reboot
EOF
done

if [[ $first_router == $last_router ]]; then
        echo -e "${G}Router ${L}p${provider}r${first_router}m${G} is up to date!${NC}"
    else
        echo -e "${G}Routers ${L}p${provider}r${first_router}m${G} to ${L}p${provider}r${last_router}m${G} are up to date!${NC}"
fi

echo -e "${C}Wait a minute until the network is running.${NC}"
sleep 2
