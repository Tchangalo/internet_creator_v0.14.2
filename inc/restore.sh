#!/bin/bash

provider=$1
first_router=$2
last_router=$3
start_delay=$4

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

if [[ $# -ne 4 ]]; then
    echo -e "${R}Error: At least one variable is empty!${NC}"
    exit 1
fi

# Stop VMs properly before restoring
for i in $(seq $first_router $last_router); do 
    VM_ID="${provider}0${provider}0$(printf '%02d' $i)"
    echo -e "${C}Stopping VM $VM_ID${NC}"
    sudo qm shutdown "$VM_ID"
done

# Check if the dump directory exists
if [ ! -d "$DUMP_DIR" ]; then
    echo -e "${R}Error: Directory $DUMP_DIR does not exist.${NC}"
    exit 1
fi

declare -A latest_backups

for vma_file in "$DUMP_DIR"/*.vma.zst; do
    VM_ID=$(basename "$vma_file" | grep -oP '(?<=vzdump-qemu-)\d+')
    timestamp=$(basename "$vma_file" | grep -oP '\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}')
    if [ -z "$VM_ID" ] || [ -z "$timestamp" ]; then
        echo -e "${R}Error: Could not extract VMID or timestamp from $vma_file.${NC}"
        exit 1
    fi
    for r in $(seq $first_router $last_router); do
        router_VM_ID="${provider}0${provider}0$(printf '%02d' $r)"
        if [[ "$VM_ID" == "$router_VM_ID" ]]; then
            if [[ "$timestamp" > "$(basename "${latest_backups[$VM_ID]}" | grep -oP '\d{4}_\d{2}_\d{2}-\d{2}_\d{2}_\d{2}')" ]]; then
                latest_backups[$VM_ID]="$vma_file"
            fi
            break
        fi
    done
done

for VM_ID in $(printf "%s\n" "${!latest_backups[@]}" | sort -n); do
    if [ -n "${latest_backups[$VM_ID]}" ]; then
        latest_vma_file="${latest_backups[$VM_ID]}"
        echo -e "${C}Restoring router $VM_ID from $latest_vma_file${NC}"
        sudo qmrestore "$latest_vma_file" "$VM_ID" --force
    else
        echo -e "${R}Error: No backup found for VM ID $VM_ID. Exiting.${NC}"
        exit 1
    fi
done

for r in $(seq $first_router $last_router); do
    VM_ID="${provider}0${provider}0$(printf '%02d' $r)"
    if [ -n "${latest_backups[$VM_ID]}" ]; then
        echo -e "${C}Starting router $VM_ID${NC}"
        sudo qm start "$VM_ID"
        sleep $start_delay
    else
        echo -e "${R}Error: No backup found for router $VM_ID, that could be restored!${NC}"
        exit 1
    fi
done

if [[ $first_router == $last_router ]]; then
    echo -e "${G}Restore of router ${L}p${provider}r${first_router}v${G} executed successfully!${NC}"
else
    echo -e "${G}Restore of routers ${L}p${provider}r${first_router}v${G} to ${L}p${provider}r${last_router}v${G} executed successfully!${NC}"
fi

echo -e "${C}Wait a minute until the network is running.${NC}"
sleep 2
