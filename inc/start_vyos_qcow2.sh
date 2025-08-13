#!/bin/bash

vm_user=$1
vm_ip=$2
version_no=$3
pve_user=$(whoami)
pve_ip=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [[ $# -ne 3 ]]; then
    echo "Error: At least one variable empty!"
    exit 1
fi

ssh ${vm_user}@${vm_ip} "sudo -A rm -rf ${HOME}/vyos-vm-images"

scp -r ${HOME}/inc/create-vms/create-vms-vyos/vyos-vm-images $vm_user@$vm_ip:/home/$vm_user

sudo rm -rf /home/${pve_user}/inc/create-vms/create-vms-vyos/vyos-${version_no}-cloud-init-10G-qemu.qcow2

#ssh-keygen -f "/home/${pve_user}/.ssh/known_hosts" -R "$vm_ip"

scp vyos_qcow2.sh ${vm_user}@${vm_ip}:/home/${vm_user}

ssh ${vm_user}@${vm_ip} "export SUDO_ASKPASS=/home/${vm_user}/askpass_script.sh && bash /home/${vm_user}/vyos_qcow2.sh $vm_user $pve_user $pve_ip $version_no"


