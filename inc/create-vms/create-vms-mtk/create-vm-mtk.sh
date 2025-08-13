#!/bin/bash

provider=$1
router=$2
major_version_no=$3
admin_password=$4

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

if [[ ${#router} -eq 1 ]]; then
    VM_ID="${provider}0${provider}00${router}"
else
    VM_ID="${provider}0${provider}0${router}"
fi

MTK_NAME="p${provider}r${router}m"
MACADDR="00:14:18:F$provider:$(printf "%02d" $router):06"
MGMT_MAC=00:24:18:A${provider}:$(printf '%02d' $router):00
MTK_IP="10.20.30.1${router}"
SSH_PUB_KEY="${HOME}/.ssh/id_ed25519.pub"

if [[ $# -ne 4 ]]; then
    exit 1
fi

# Destroy MTK
echo -e "${C}Stopping and destroying router $VM_ID (if it exists)${NC}"
sudo qm stop $VM_ID || true
sudo qm destroy $VM_ID || true
sleep 1

# Create MTK
sudo qm create $VM_ID --name $MTK_NAME --ostype other --memory 2048 --balloon 2000 --cpu host --cores 4 --scsihw virtio-scsi-single \
--net0 virtio,bridge=vmbr1001,macaddr="${MGMT_MAC}" \
--net6 virtio,bridge=vmbr0,macaddr="$MACADDR"

# Add interfaces
echo -e "${C}Adding interfaces and VLAN-tags to router $VM_ID${NC}"

# Hashmap
declare -A vlan_map=(
    [1101]=910  [1102]=810  [1103]=1103  [1104]=1104
    [1111]=1011 [1112]=1112 [1113]=112   [1114]=111
    [1121]=112  [1122]=1122 [1123]=1123  [1124]=212
)

for net in {1..4}; do
    key="${provider}${router}${net}"
    vlanid=${vlan_map[$key]}
    # if [[ -n "$vlanid" ]]; then
          sudo qm set $VM_ID --net${net} virtio,bridge=vmbr${provider},tag=${vlanid},macaddr=00:${provider}4:18:F${provider}:$(printf '%02d' $router):$(printf '%02d' $net)
    # else
    #     sudo qm set $VM_ID --net${net} virtio,bridge=vmbr${provider},macaddr=00:${provider}4:18:F${provider}:$(printf '%02d' $router):$(printf '%02d' $net)
    # fi
done

# Check for latest MikroTik-CHR URL
LATEST_URL=$(curl -s https://mikrotik.com/download | grep -oP "https://download.mikrotik.com/routeros/${major_version_no}\.\d+(\.\d+){0,2}/chr-${major_version_no}\.\d+(\.\d+){0,2}\.img\.zip" | head -n 1)
LATEST_FILE="$(basename "$LATEST_URL" .zip)"

if [[ -z "$LATEST_URL" ]]; then
    echo -e "${R}Error: Could not retrieve the download URL. Please check the MikroTik website.${NC}"
    exit 1
fi

IMG_DIR="${HOME}/inc/create-vms/create-vms-mtk/mtk-images"

# Check if a newer image is available
if [[ ! -f "$IMG_DIR/$LATEST_FILE" ]]; then
    sudo rm -r $IMG_DIR
    sudo mkdir $IMG_DIR
    sudo chown user:user $IMG_DIR
    echo -e "${C}Found new Image. Downloading...${NC}"
    sudo wget -q -O "$IMG_DIR/$LATEST_FILE.zip" "$LATEST_URL"
    sudo apt install -y unzip
    sudo unzip -o "$IMG_DIR/$LATEST_FILE.zip" -d "$IMG_DIR"
    sudo rm "$IMG_DIR/$LATEST_FILE.zip"
    sudo chown user:user $IMG_DIR/*.img
fi

IMG_FILE="$IMG_DIR/$LATEST_FILE"
    
# Convert image to RAW format
RAW_FILE="$IMG_DIR/${LATEST_FILE%}.raw"
sudo qemu-img resize -f raw "$IMG_FILE" 8G
sudo qemu-img convert "$IMG_FILE" "$RAW_FILE"

# Import disk into VM
FSTYPE=$(findmnt -n -o FSTYPE /)
if [[ "$FSTYPE" == "zfs" ]]; then
    sudo qm importdisk $VM_ID "$RAW_FILE" local-zfs
    sudo qm set $VM_ID --virtio0 local-zfs:vm-$VM_ID-disk-0
elif [[ "$FSTYPE" == "ext4" ]]; then
    sudo qm importdisk $VM_ID "$RAW_FILE" local-lvm
    sudo qm set $VM_ID --virtio0 local-lvm:vm-$VM_ID-disk-0
elif [[ "$FSTYPE" == "btrfs" ]]; then
    sudo qm importdisk $VM_ID "$RAW_FILE" local-btrfs
    sudo qm set $VM_ID --virtio0 local-btrfs:$VM_ID/vm-$VM_ID-disk-0.raw
else
    echo -e "${R}Unknown filesystem type: $FSTYPE${NC}"
    exit 1
fi

sudo rm "$RAW_FILE"
sudo qm set $VM_ID --boot order=virtio0

# Start VM
sudo qm start $VM_ID
echo -e "${C}Waiting for $MTK_NAME to boot${NC}"

# Sleeping
while true; do
    sleep 3
    if ping -c 1 -W 1 "$MTK_IP" &>/dev/null; then
        break
    fi
    echo -e "${C}Still waiting for $MTK_NAME ...${NC}"
done
echo -e "${C}$MTK_NAME is running ${NC}"

ssh-keygen -f "/home/user/.ssh/known_hosts" -R "$MTK_IP"

# Set the admin password and enable SSH
ssh -o StrictHostKeyChecking=no admin@$MTK_IP << EOF
/system identity set name="p${provider}r${router}m"
/user set admin password=$admin_password
/ip service enable ssh
EOF

# Wait a moment for the changes to take effect
sleep 3

# Copy the SSH key to the MikroTik router
sshpass -p "$admin_password" scp "$SSH_PUB_KEY" admin@$MTK_IP:/id_ed25519.pub

# Import the SSH key on MikroTik
sshpass -p "$admin_password" ssh admin@$MTK_IP << EOF
/user ssh-keys import public-key-file=id_ed25519.pub user=admin
EOF

# Test SSH login without a password
ssh -o PasswordAuthentication=no admin@$MTK_IP "echo 'SSH Key passed successfully!'"

# Configure
if [[ "$router" == "10" ]]; then
    ssh admin@$MTK_IP << EOF
    /interface set ether2 name=p1r9v
    /interface set ether3 name=p1r8v
    /interface set ether6 name=external_main_router

    /ip address add address=10.1.255.10/32 interface=lo
    /ip address add address=10.8.10.10/24 interface=p1r8v
    /ip address add address=10.9.10.10/24 interface=p1r9v
    /ip address add address=192.168.10.110/24 interface=external_main_router
    
    /ip dns set servers=1.1.1.1,9.9.9.9 allow-remote-requests=yes

    /routing ospf instance add disabled=no name=ospf-instance-v4 router-id=10.1.255.10
    /routing ospf area add disabled=no instance=ospf-instance-v4 name=0.0.0.0

    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r8v networks=10.8.10.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r9v networks=10.9.10.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=lo networks=10.1.255.10/32

    $(for i in {1..8}; do
        echo "/routing bgp template add name=my-bgp-template as=65001 router-id=10.1.255.10"
        echo "/routing bgp connection add name=p1r${i}v template=my-bgp-template local.address=10.1.255.10 local.role=ibgp-rr remote.address=10.1.255.${i} remote.as=65001 nexthop-choice=force-self"
    done)
    
    $(for i in 11 12; do
        echo "/routing bgp template add name=my-bgp-template as=65001 router-id=10.1.255.10"
        echo "/routing bgp connection add name=p1r${i}v template=my-bgp-template local.address=10.1.255.10 local.role=ibgp-rr remote.address=10.1.255.${i} remote.as=65001 nexthop-choice=force-self"
    done)
EOF

elif [[ "$router" == "11" ]]; then
    ssh admin@$MTK_IP << EOF
    /interface set ether2 name=pfSense
    /interface set ether4 name=p1r12m
    /interface set ether5 name=p1r1v
    /interface set ether6 name=external_main_router

    /ip dhcp-client add interface=pfSense disabled=no
    /ip firewall nat add chain=srcnat out-interface=pfSense action=masquerade

    /ip address add address=10.1.255.11/32 interface=lo
    /ip address add address=10.1.11.11/24 interface=p1r1v
    /ip address add address=10.11.12.11/24 interface=p1r12m
    /ip address add address=192.168.10.111/24 interface=external_main_router
    
    /ip dns set servers=1.1.1.1,9.9.9.9 allow-remote-requests=yes

    /routing ospf instance add disabled=no name=ospf-instance-v4 router-id=10.1.255.11
    /routing ospf instance set 0 originate-default=if-installed
    /routing ospf area add disabled=no instance=ospf-instance-v4 name=0.0.0.0

    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r1v networks=10.1.11.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r12m networks=10.11.12.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=lo networks=10.1.255.11/32

    /routing bgp template add name=my-bgp-template as=65001 router-id=10.1.255.11
    /routing bgp connection add name=p1r9v template=my-bgp-template local.address=10.1.255.11 local.role=ibgp remote.address=10.1.255.9 remote.as=65001 nexthop-choice=force-self
    /routing bgp connection add name=p1r10m template=my-bgp-template local.address=10.1.255.11 local.role=ibgp remote.address=10.1.255.10 remote.as=65001 nexthop-choice=force-self
EOF

elif [[ "$router" == "12" ]]; then
    ssh admin@$MTK_IP << EOF
    /interface set ether2 name=p1r11m
    /interface set ether5 name=p1r2v
    /interface set ether6 name=external_main_router

    /ip address add address=10.1.255.12/32 interface=lo
    /ip address add address=10.11.12.12/24 interface=p1r11m
    /ip address add address=10.2.12.12/24 interface=p1r2v
    /ip address add address=192.168.10.112/24 interface=external_main_router
    
    /ip dns set servers=1.1.1.1,9.9.9.9 allow-remote-requests=yes

    /routing ospf instance add disabled=no name=ospf-instance-v4 router-id=10.1.255.12
    /routing ospf area add disabled=no instance=ospf-instance-v4 name=0.0.0.0

    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r11m networks=10.11.12.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=p1r2v networks=10.2.12.0/24
    /routing ospf interface-template add area=0.0.0.0 interfaces=lo networks=10.1.255.12/32

    /routing bgp template add name=my-bgp-template as=65001 router-id=10.1.255.12
    /routing bgp connection add name=p1r9v template=my-bgp-template local.address=10.1.255.12 local.role=ibgp remote.address=10.1.255.9 remote.as=65001 nexthop-choice=force-self
    /routing bgp connection add name=p1r10m template=my-bgp-template local.address=10.1.255.12 local.role=ibgp remote.address=10.1.255.10 remote.as=65001 nexthop-choice=force-self
EOF
fi

echo -e "${G}MikroTik router ${L}$MTK_NAME${G} has been successfully set up and configured!${NC}"
sleep 2
