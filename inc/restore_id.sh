#!/bin/bash

vmid=$1

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

FSTYPE=$(findmnt -n -o FSTYPE /)

if [[ "$FSTYPE" == "zfs" || "$FSTYPE" == "ext4" ]]; then
    DUMP_DIR="/var/lib/vz/dump"
elif [[ "$FSTYPE" == "btrfs" ]]; then
	DUMP_DIR="/var/lib/pve/local-btrfs/dump"
fi

if [ -z "$vmid" ]; then
    echo -e "${R}Error: vmid was left empty!${NC}"
    exit 1
fi

# Check if the dump directory exists
if [ ! -d "$DUMP_DIR" ]; then
    echo -e "${R}Error: Directory $DUMP_DIR does not exist.${NC}"
    exit 1
fi

# Find the latest backup for the specified VMID
latest_backup=""
latest_timestamp=""

for vma_file in "$DUMP_DIR"/*.vma.zst; do
    # Extract the VMID and timestamp from the filename
    VM_ID=$(basename "$vma_file" | grep -oP '(?<=vzdump-qemu-)\d+')
    timestamp=$(basename "$vma_file" | grep -oP '\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}')

    if [[ "$VM_ID" == "$vmid" ]]; then
        if [[ -z "$latest_backup" || "$timestamp" > "$latest_timestamp" ]]; then
            latest_backup="$vma_file"
            latest_timestamp="$timestamp"
        fi
    fi
done

if [ -z "$latest_backup" ]; then
    echo -e "${R}Error: No backup found for VM $vmid, that could be restored!${NC}"
    exit 1
fi

## Uncomment the lines below, if the VM should be destroyed before the restore process:
# echo -e "${C}Destroying VM${NC}"
sudo qm stop $vmid
# sudo qm destroy $vmid

echo -e "${C}Restoring VM $vmid from $latest_backup${NC}"
sudo qmrestore "$latest_backup" "$vmid" --force

echo -e "${C}Starting VM $vmid${NC}"
sudo qm start "$vmid"

echo -e "${G}Restore of VM ${L}$vmid${G} executed successfully!${NC}"
echo -e "${C}Wait a minute until the VM is running.${NC}"
sleep 2