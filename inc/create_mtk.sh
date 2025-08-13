#!/bin/bash

provider=$1
first_router=$2
last_router=$3
major_version_no=$4
admin_password=$5

C='\033[0;94m'
NC='\033[0m'

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <provider> <router> <major_version_no (e.g., 7)> <admin_password>"
    exit 1
fi

for router in $(seq $first_router $last_router); do
    bash ${HOME}/inc/create-vms/create-vms-mtk/create-vm-mtk.sh $provider $router $major_version_no $admin_password
done

echo -e "${C}Wait a minute until the network is running.${NC}"
sleep 2