#!/bin/bash

provider=$1
first_router=$2
last_router=$3
delete_all_backups=$4

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

if [[ $# -ne 4 ]]; then
    echo -e "${R}Error: At least one variable empty!${NC}"
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
	for i in $(seq $first_router $last_router); do
		VM_ID="${provider}0${provider}0$(printf '%02d' $i)"
		# Check, if image with VMID exists in IMG_DIR
		if ! ls "$IMG_DIR" | grep -q "^vm-${VM_ID}-disk-"; then
			echo -e "${R}Error: VM $VM_ID does not exist!${NC}"
			exit 1
		fi
		if [[ "$delete_all_backups" == "true" ]] && [[ "$i" == "$first_router" ]]; then
			echo -e "${C}Deleting ALL existing backups${NC}"
			if [[ -d "$DUMP_DIR" ]]; then
				sudo rm -rf $DUMP_DIR
			fi
			sudo mkdir -p $DUMP_DIR
		fi
		echo -e "${C}Backing up VM ${VM_ID}${NC}"
		sudo vzdump "$VM_ID" --dumpdir $DUMP_DIR --mode snapshot --compress zstd
	done
elif [[ "$FSTYPE" == "btrfs" ]]; then
	for i in $(seq $first_router $last_router); do
			VM_ID="${provider}0${provider}0$(printf '%02d' $i)"
		if ! ls "$IMG_DIR" | grep -q "^${VM_ID}.*"; then
			echo -e "${R}Error: VM $VM_ID does not exist!${NC}"
			exit 1
		fi
		if [[ "$delete_all_backups" == "true" ]] && [[ "$i" == "$first_router" ]]; then
			echo -e "${C}Deleting ALL existing backups${NC}"
			sudo rm -rf "$DUMP_DIR"/*
			sudo mkdir -p "$DUMP_DIR"
		fi
		echo -e "${C}Backing up router ${VM_ID}${NC}"
		sudo vzdump $VM_ID --dumpdir $DUMP_DIR --mode snapshot --compress zstd
	done
fi

if [[ "$delete_all_backups" == "true" ]]; then
	if [[ $first_router == $last_router ]]; then
		echo -e "${G}Deletion of ALL existing backups and backup of router ${L}p${provider}r${first_router}v${G} executed successfully!${NC}"
	else
		echo -e "${G}Deletion of ALL existing backups and backups of routers ${L}p${provider}r${first_router}v${G} to ${L}p${provider}r${last_router}v${G} executed successfully!${NC}"
	fi
else
	if [[ $first_router == $last_router ]]; then
		echo -e "${G}Backup of router ${L}p${provider}r${first_router}v${G} executed successfully!${NC}"
	else
		echo -e "${G}Backups of routers ${L}p${provider}r${first_router}v${G} to ${L}p${provider}r${last_router}v${G} executed successfully!${NC}"
	fi
fi