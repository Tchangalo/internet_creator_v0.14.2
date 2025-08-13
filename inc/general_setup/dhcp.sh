#!/bin/bash

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
RO='\e[38;5;205m'
R='\033[91m'
NC='\033[0m'

node_number=$1
iso_name=$2

# Detect the filesystem type of the root directory
FSTYPE=$(findmnt -n -o FSTYPE /)

# Check if the input is a valid number
if [[ ! "$node_number" =~ ^[0-9]+$ ]]; then
    echo -e "${RO}Error: Invalid input. Please enter a valid number.${NC}"
    echo -e "${RO}A valid input is a non-negative integer (e.g. 1, 2, 3).${NC}"
    exit 1
fi

VM_ID=${node_number}07999
VM_NAME="dhcp${node_number}"
ISO_PATH="/var/lib/vz/template/iso/$iso_name"
MEMORY=1536
BALLON=1500
CPU="host"
CORES=4
SCSIHW="virtio-scsi-pci"
NET_CONFIG="virtio,bridge=vmbr0,macaddr=00:24:18:0A:C${node_number}:DE"

# Determine storage location based on filesystem type
if [[ "$FSTYPE" == "zfs" ]]; then
    STORAGE="local-zfs"
elif [[ "$FSTYPE" == "ext4" ]]; then
    STORAGE="local-lvm"
elif [[ "$FSTYPE" == "btrfs" ]]; then
    STORAGE="local-btrfs"
    ISO_PATH="/var/lib/pve/local-btrfs/template/iso/${iso_name}"
else
    echo -e "${R}Unknown filesystem type: $FSTYPE${NC}"
    exit 1
fi

# Destroy
echo -e "${C}Stopping and destroying VM $VM_ID (if it exists)${NC}"
sudo qm stop $VM_ID || true
sudo qm destroy $VM_ID || true

# Create
echo -e "${C}Creating VM $VM_ID${NC}"
sudo qm create $VM_ID --name $VM_NAME --ostype l26 --memory $MEMORY --balloon $BALLON --cpu $CPU --cores $CORES --scsihw $SCSIHW --virtio0 "$STORAGE:12,discard=on" --net0 "$NET_CONFIG"

# Set the ISO and boot options
sudo qm set $VM_ID --ide2 "$ISO_PATH,media=cdrom"
sudo qm set $VM_ID --boot order=ide2

# Configure additional network and agent options
sudo qm set $VM_ID -net1 model=virtio,bridge=vmbr1001,firewall=0
sudo qm set $VM_ID --agent enabled=1

# Start
sudo qm start $VM_ID

echo -e "${G}VM ${L}$VM_ID ${G}(${L}$VM_NAME${G}) has been created and started successfully!${NC}"
echo -e "${C}After installation, STOP (not shutdown!) the VM and execute DHCP Server Postinstall and Configuration.${NC}"