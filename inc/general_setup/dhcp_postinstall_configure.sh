#!/bin/bash

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
RO='\e[38;5;205m'
R='\033[91m'
NC='\033[0m'

dhcp_server_ip=$1
dhcp_user=$2
dhcp_user_password=$3
pve_user_password=$4
pve_ip=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
pve_hostname=$(hostname -s)

node_number="${dhcp_server_ip: -1}"

# Check if the input is a valid number
if [[ ! "$node_number" =~ ^[0-9]+$ ]]; then
    echo -e "${RO}Error: Invalid input. Please enter a valid number.${NC}"
    echo -e "${RO}A valid input is a non-negative integer (e.g. 1, 2, 3).${NC}"
    exit 1
fi

VM_ID=${node_number}07999

if [[ $# -ne 4 ]]; then
    echo -e "${R}Error: At least one variable is empty!${NC}"
    exit 1
fi

# Postinstall
sudo qm stop $VM_ID
sudo qm set $VM_ID -delete ide2
sudo qm set $VM_ID -boot order=virtio0
sudo qm set $VM_ID -onboot 1
sleep 2

# Start
ssh-keygen -f "/home/user/.ssh/known_hosts" -R "$dhcp_server_ip"
sudo qm start $VM_ID
sleep 14

ssh $dhcp_user@$dhcp_server_ip << EOF
touch askpass_script.sh
echo "#!/bin/bash
echo '"$dhcp_user_password"'" > askpass_script.sh
chmod +x /home/$dhcp_user/askpass_script.sh
chmod 700 /home/$dhcp_user/askpass_script.sh
EOF

ssh-copy-id $dhcp_user@$dhcp_server_ip

scp ${HOME}/inc/general_setup/dhcp_configure.sh $dhcp_user@$dhcp_server_ip:/home/$dhcp_user

ssh $dhcp_user@$dhcp_server_ip "export SUDO_ASKPASS=/home/$dhcp_user/askpass_script.sh && bash /home/$dhcp_user/dhcp_configure.sh $pve_ip $pve_hostname $pve_user_password"

ssh $dhcp_user@$dhcp_server_ip "sudo reboot"

echo -e "${G}DHCP-server ${L}$VM_ID ${G} has been set up and configured successfully!${NC}"

sleep 2