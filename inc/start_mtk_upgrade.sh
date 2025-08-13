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

for r in $(seq $first_router $last_router); do
    sudo  bash ${HOME}/inc/mtk_upgrade.sh $provider $r
done

echo -e "${C}Wait a minute until the network is running.${NC}"
sleep 2
