#!/bin/bash

export ANSIBLE_HOST_KEY_CHECKING=False

provider=$1
first_router=$2
last_router=$3
release_type=$4

if [[ $release_type == "rolling" ]]; then
    IMAGE_DIR="${HOME}/inc/ansible/vyos-images-rolling"
    IMG_FOLDER_NAME="vyos-images-rolling"
else
    IMAGE_DIR="${HOME}/inc/ansible/vyos-images-stream"
    IMG_FOLDER_NAME="vyos-images-stream"
fi

limit_elements=""
for e in $(seq $first_router $last_router); do
    limit_elements+="p${provider}r${e}v,"
done
limit_elements=${limit_elements%,}
vyos_ansible_limit="-l $limit_elements"

C='\033[0;94m'
G='\033[0;32m'
L='\033[38;5;135m'
R='\033[91m'
NC='\033[0m'

sleeping () {
    for r in $(seq "$first_router" "$last_router"); do
        while true; do
            sleep 1
            if ansible -i "/home/user/inc/ansible/inventories/inventory${provider}.yaml" "p${provider}r${r}v" -m ping -u vyos | grep -q pong; then
                break
            fi
        done
        echo -e "${C}Router ${r} is running${NC}"
    done
}

if [[ $# -ne 4 ]]; then
    echo -e "${R}Error: At least one variable empty!${NC}"
    exit 1
fi

# Destroy and create vms
cd ${HOME}/inc/create-vms/create-vms-vyos/
for r in $(seq $first_router $last_router); do
    sudo bash create-vm-vyos.sh $provider $r
done

# Start routers
echo -e "${C}Starting router$([[ $first_router != $last_router ]] && echo s)${NC}"
for r in $(seq $first_router $last_router); do
    sudo qm start ${provider}0${provider}00${r}
    ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "10.20.30.${provider}${r}"
done

# Sleeping
echo -e "${C}Waiting for first boot${NC}"
sleeping

# Download latest vyos image and upgrade
cd ${HOME}/inc/ansible
echo -e "${C}Downloading latest VyOS image (if necessary) and system upgrade$([[ $first_router != $last_router ]] && echo s)${NC}"
ansible-playbook -i inventories/inventory${provider}.yaml vyos_upgrade_fast.yml -e "release_type=$release_type" "$vyos_ansible_limit"

# Delete old image in vyos-images
cd $image_dir || { echo -e "${R}Directory not found${NC}"; exit 1; }
image_count=$(ls vyos-*.iso 2>/dev/null | wc -l)

if [ "$image_count" -gt 1 ]; then
    latest_image=$(ls -1 vyos-*.iso | while read -r file; do
        echo "$(stat -c "%Z %n" "$file")"
    done | sort -nr | head -n 1 | cut -d' ' -f2-)

    for image in vyos-*.iso; do
        if [ "$image" != "$latest_image" ]; then
            rm -f "$image"
            echo -e "${C}Deleted from folder $IMG_FOLDER_NAME: $image${NC}"
        fi
    done
else
    echo -e "${C}Only one image found in folder $IMG_FOLDER_NAME, no deletion needed.${NC}"
fi

# Reboot
echo -e "${C}Reboot${NC}"
cd ${HOME}/inc/ansible
ansible-playbook -i inventories/inventory${provider}.yaml vyos_reboot.yml "$vyos_ansible_limit"

# Sleeping
echo -e "${C}Waiting for second boot${NC}"
sleeping

# Remove old images from routers
cd ${HOME}/inc/ansible
echo -e "${C}Removing old images from router$([[ $first_router != $last_router ]] && echo s)${NC}"
ansible-playbook -i inventories/inventory${provider}.yaml vyos_remove_images.yml "$vyos_ansible_limit"

# Show remaining image
echo -e "${C}Remaining image on router$([[ $first_router != $last_router ]] && echo s):${NC}"
ansible-playbook -i inventories/inventory${provider}.yaml vyos_show_image.yml "$vyos_ansible_limit"

# Configuring
echo -e "${C}Configuring network${NC}"
ansible-playbook -i inventories/inventory${provider}.yaml vyos_configure_fast.yml "$vyos_ansible_limit"

# Delete cdrom(s)
echo -e "${C}Deleting cdrom$([[ $first_router != $last_router ]] && echo s)${NC}"
for r in $(seq $first_router $last_router); do
    sudo qm set ${provider}0${provider}00$r --delete ide2
done

# Reboot
echo -e "${C}Final reboot${NC}"
echo -e "${C}Shutting down router$([[ $first_router != $last_router ]] && echo s)${NC}"
sudo  bash ${HOME}/inc/controls/shutdown.sh $provider $first_router $last_router
echo -e "${C}Final restart${NC}"
sudo  bash ${HOME}/inc/controls/start.sh $provider $first_router $last_router 0

if [[ $first_router == $last_router ]]; then
	echo -e "${G}Creation of router ${L}p${provider}r${first_router}v${G} executed successfully!${NC}"
else
	echo -e "${G}Creation of routers ${L}p${provider}r${first_router}v${G} to ${L}p${provider}r${last_router}v${G} executed successfully!${NC}"
fi
echo -e "${C}Wait a minute until the network is running.${NC}"
sleep 2
