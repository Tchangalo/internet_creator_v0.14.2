#!/bin/bash

vm_id=$1
delete_all_backups=$2

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

if [ -z "$vm_id" ]; then
    echo -e "${R}Error: VM-ID was left empty!${NC}"
    exit 1
fi

FSTYPE=$(findmnt -n -o FSTYPE /)

if [[ "$FSTYPE" == "zfs" ]]; then
	IMG_DIR="/dev/zvol/rpool/data"
elif [[ "$FSTYPE" == "ext4" ]]; then
    IMG_DIR="/dev/pve" 
elif [[ "$FSTYPE" == "btrfs" ]]; then
    IMG_DIR="/var/lib/pve/local-btrfs/images"
else
    echo "Unknown filesystem type: $FSTYPE"
    exit 1
fi

if [[ "$FSTYPE" == "zfs" || "$FSTYPE" == "ext4" ]]; then
    DUMP_DIR="/var/lib/vz/dump"
elif [[ "$FSTYPE" == "btrfs" ]]; then
	DUMP_DIR="/var/lib/pve/local-btrfs/dump"
fi


if [[ "$FSTYPE" == "zfs" || "$FSTYPE" == "ext4" ]]; then
    if ! ls "$IMG_DIR" | grep -q "^vm-${vm_id}-disk-"; then
        echo -e "${R}Error: Router $vm_id does not exist!${NC}"
        exit 1
    fi
    if [[ "$delete_all_backups" == "true" ]]; then
        echo -e "${C}Deleting ALL existing backups${NC}"
        if [[ -d "$DUMP_DIR" ]]; then
            sudo rm -rf $DUMP_DIR
        fi
        sudo mkdir -p $DUMP_DIR
    fi
    echo -e "${C}Backing up VM $vm_id${NC}"
    sudo vzdump $vm_id --dumpdir /var/lib/vz/dump --mode snapshot --compress zstd
elif [[ "$FSTYPE" == "btrfs" ]]; then
	if ! ls "$IMG_DIR" | grep -q "^${vm_id}.*"; then
		echo -e "${R}Error: Router $vm_id does not exist!${NC}"
		exit 1
	fi
    if [[ "$delete_all_backups" == "true" ]]; then
    echo -e "${C}Deleting ALL existing backups${NC}"
        if [[ -d "$DUMP_DIR" ]]; then
            sudo rm -rf $DUMP_DIR
        fi
        sudo mkdir -p $DUMP_DIR
    fi
    echo -e "${C}Backing up router $vm_id${NC}"
	sudo vzdump $vm_id --dumpdir /var/lib/pve/local-btrfs/dump --mode snapshot --compress zstd
fi

if [[ "$delete_all_backups" == "true" ]];then
    echo -e "${G}Deletion of ALL existing backups and backup of VM ${L}$vm_id${G} executed successfully!${NC}"
else
    echo -e "${G}Backup of VM ${L}$vm_id${G} executed successfully!${NC}"
fi