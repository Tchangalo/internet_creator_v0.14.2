#!/bin/bash

provider=$1
router=$2

if [[ $# -ne 2 ]]; then
    exit 1
fi

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

FSTYPE=$(findmnt -n -o FSTYPE /)

if [[ "$FSTYPE" == "zfs" ]]; then
	IMPORT_DEST="local-zfs"
elif [[ "$FSTYPE" == "ext4" ]]; then
    IMPORT_DEST="local-lvm"
elif [[ "$FSTYPE" == "btrfs" ]]; then
    IMPORT_DEST="local-btrfs"
else
    echo "Unknown filesystem type: $FSTYPE"
    exit 1
fi

vmid=${provider}0${provider}0$(printf '%02d' $router)
mgmtmac=00:24:18:A${provider}:$(printf '%02d' $router):00

# Destroy VyOS
echo -e "${C}Stopping and destroying router $vmid (if it exists)${NC}"
qm stop $vmid || true
qm destroy $vmid || true

# Create VyOS
echo -e "${C}Creating router $vmid${NC}"
qm create $vmid --name "p${provider}r${router}v" --ostype l26 --memory 1664 --balloon 1664 --cpu cputype=host --cores 4 --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr1001,macaddr="${mgmtmac}"
if [[ "$FSTYPE" == "zfs" ]]; then
    qm importdisk $vmid vyos-1.5.0-cloud-init-10G-qemu.qcow2 $IMPORT_DEST
    qm set $vmid --virtio0 $IMPORT_DEST:vm-$vmid-disk-0
elif [[ "$FSTYPE" == "ext4" ]]; then
    qm importdisk $vmid vyos-1.5.0-cloud-init-10G-qemu.qcow2 $IMPORT_DEST
    qm set $vmid --virtio0 $IMPORT_DEST:vm-$vmid-disk-0
elif [[ "$FSTYPE" == "btrfs" ]]; then
    qm importdisk $vmid vyos-1.5.0-cloud-init-10G-qemu.qcow2 local-btrfs
    qm set $vmid --virtio0 $IMPORT_DEST:$vmid/vm-$vmid-disk-0.raw
fi
qm set $vmid --boot order=virtio0

# Add interfaces
echo -e "${C}Adding interfaces and VLAN-tags to router $vmid${NC}"

# Hashmap
declare -A vlan_map=(
    [111]=1011 [112]=111  [113]=12   [114]=15
    [121]=12   [122]=212  [123]=23   [124]=26
    [131]=23   [132]=1032 [133]=34   [134]=37
    [141]=34   [142]=1042 [143]=1043 [144]=48
    [151]=1051 [152]=15   [153]=56   [154]=1054
    [161]=56   [162]=26   [163]=67   [164]=1064
    [171]=67   [172]=37   [173]=78   [174]=79
    [181]=78   [182]=48   [183]=1083 [184]=810
    [191]=1091 [192]=79   [193]=910  [194]=1094

    [211]=2011 [212]=2012 [213]=212  [214]=215
    [221]=212  [222]=2022 [223]=223  [224]=226
    [231]=223  [232]=2032 [233]=234  [234]=237
    [241]=234  [242]=2042 [243]=2043 [244]=248
    [251]=2051 [252]=215  [253]=256  [254]=2054
    [261]=256  [262]=226  [263]=267  [264]=2064
    [271]=267  [272]=237  [273]=278  [274]=279
    [281]=278  [282]=248  [283]=2083 [284]=2084
    [291]=2091 [292]=279  [293]=2093 [294]=2094

    [311]=3011 [312]=3012 [313]=312  [314]=315
    [321]=312  [322]=3022 [323]=323  [324]=326
    [331]=323  [332]=3032 [333]=334  [334]=337
    [341]=334  [342]=3042 [343]=3043 [344]=348
    [351]=3051 [352]=315  [353]=356  [354]=3054
    [361]=356  [362]=326  [363]=367  [364]=3064
    [371]=367  [372]=337  [373]=378  [374]=379
    [381]=378  [382]=348  [383]=3083 [384]=3084
    [391]=3091 [392]=379  [393]=3093 [394]=3094
)

for net in {1..4}; do
    key="${provider}${router}${net}"
    vlanid=${vlan_map[$key]}
    sudo qm set $vmid --net${net} virtio,bridge=vmbr${provider},tag=${vlanid},macaddr=00:${provider}4:18:F${provider}:$(printf '%02d' $router):$(printf '%02d' $net)
done

# Import seed.iso
echo -e "${C}Importing seed.iso for router $vmid${NC}"

if [[ "$FSTYPE" == "zfs" || "$FSTYPE" == "ext4" ]]; then
    qm set $vmid --ide2 media=cdrom,file=local:iso/seed.iso
elif [[ "$FSTYPE" == "btrfs" ]]; then
    qm set $vmid --ide2 media=cdrom,file=local-btrfs:iso/seed.iso
fi
#qm set $vmid --onboot 1

