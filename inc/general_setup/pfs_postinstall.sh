#!/bin/bash

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
RO='\e[38;5;205m'
R='\e[31m'
NC='\033[0m'

node_number=$1
node_arrangement=$2

# Array for newly created bridges
new_bridges=()

# Check if the input is a valid number
if [[ ! "$node_number" =~ ^[0-9]+$ ]]; then
    echo -e "${RO}Error: Invalid input. Please enter a valid number.${NC}"
    echo -e "${RO}A valid input should be a non-negative integer (e.g. 1, 2, 3).${NC}"
    exit 1
fi

VM_ID=${node_number}000

run_or_fail() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo -e "${R}Error: Command failed -> $*${NC}"
        exit $status
    fi
}

add_auto_if_missing() {
    local iface="$1"
    if ! grep -q -E "^auto[[:space:]]+$iface" /etc/network/interfaces; then
        sudo sed -i "/^iface[[:space:]]\+$iface/ i auto $iface" /etc/network/interfaces
    fi
}

create_bridge_if_missing() {
    local name="$1"
    shift
    if ! grep -q -m1 -E "^iface[[:space:]]+$name" /etc/network/interfaces; then
        echo -e "${C}Creating bridge $name${NC}"
        sudo pvesh create /nodes/$(hostname)/network \
            -type bridge \
            -iface "$name" \
            "$@"
        add_auto_if_missing "$name"
        new_bridges+=("$name")
    else
        echo -e "${L}Bridge $name already exists. Skipping creation.${NC}"
        add_auto_if_missing "$name"
    fi
}

# Create management bridge (with IP)
create_bridge_if_missing vmbr1001 -cidr 10.20.30.254/24 -autostart 1 -comments "MGMT$node_number"

# Create LAN bridges without physical ports
if [ "$node_arrangement" == "cluster" ]; then
    create_bridge_if_missing "vmbr${node_number}" -autostart 1 -bridge_vlan_aware 1 -comments "LAN${node_number}"
else
    for net in 1 2 3; do
        create_bridge_if_missing "vmbr${net}" -autostart 1 -bridge_vlan_aware 1 -comments "LAN${net}"
    done
fi

# If new bridges were created → reload only these
if [ ${#new_bridges[@]} -gt 0 ]; then
    echo -e "${C}Reloading network configuration for new bridges...${NC}"
    allow_args=()
    for br in "${new_bridges[@]}"; do
        allow_args+=( --allow "$br" )
    done
    sudo ifreload "${allow_args[@]}"
    echo -e "${C}Please reload the PVE-GUI page and then execute 'Apply Configuration' in the Network section. Then press Enter here.${NC}"
    read
fi

# Setup interfaces on pfSense
run_or_fail sudo qm set $VM_ID -delete ide2
run_or_fail sudo qm set $VM_ID -boot order=virtio0
run_or_fail sudo qm set $VM_ID -net0 model=virtio,bridge=vmbr0,firewall=0,macaddr=00:24:18:0A:${node_number}B:DE

if [ "$node_arrangement" == "cluster" ]; then
    run_or_fail sudo qm set $VM_ID --net$node_number virtio,bridge=vmbr$node_number,tag=${node_number}011
else
    for net in {1..3}; do
        run_or_fail sudo qm set $VM_ID --net$net virtio,bridge=vmbr$net,tag=${net}011
    done
fi

run_or_fail sudo qm set $VM_ID -onboot 1
run_or_fail sudo qm start $VM_ID

echo -e "${G}Firewall ${L}$VM_ID${G} has been set up successfully!
${C}Now open the console and configure manually.${NC}"
