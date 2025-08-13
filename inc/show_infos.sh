#!/bin/bash

provider=$1
router=$2

if [[ $router -lt 10 ]]; then
    rid="p${provider}r${router}v"
    ssh_output1=$(ssh -o ConnectTimeout=5 "$rid" "cli-shell-api showCfg" 2>&1)
    ssh_output2=$(ssh -o ConnectTimeout=5 "$rid" "ip route" 2>&1)
    ssh_output3=$(ssh -o ConnectTimeout=5 "$rid" "ip rule" 2>&1)
    ssh_output4=$(ssh -o ConnectTimeout=5 "$rid" "ip neigh show" 2>&1)
    ssh_output5=$(ssh -o ConnectTimeout=5 "$rid" "ip -br addr show" 2>&1)
    ssh_output6=$(ssh -o ConnectTimeout=5 "$rid" "ip -br link show" 2>&1)
    ssh_output7=$(ssh -o ConnectTimeout=5 "$rid" "ip vrf show" 2>&1)

    echo
    echo "CONFIGURATION of $rid:"
    echo
    echo "$ssh_output1"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "ROUTING TABLE of $rid:"
    echo
    echo "$ssh_output2"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "ROUTING RULES of $rid:"
    echo
    echo "$ssh_output3"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "ARP TABLE of $rid:"
    echo
    echo "$ssh_output4"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "IPs of $rid:"
    echo
    echo "$ssh_output5"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "INTERFACES of $rid:"
    echo
    echo "$ssh_output6"
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "VRF of $rid:"
    echo
    echo "$ssh_output7"
    echo "------------------------------------------------------------------------------------------------------------------------"     

else
    rid="p${provider}r${router}m"
    MIKROTIK_IP="10.20.30.1${router}"

    echo "CONFIGURATION of $rid:"
    echo
    ssh -o StrictHostKeyChecking=no admin@"$MIKROTIK_IP" <<EOF
export
EOF
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "ROUTING TABLE of $rid:"
    echo
    ssh -o StrictHostKeyChecking=no admin@"$MIKROTIK_IP" <<EOF
ip route print
EOF
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "ARP TABLE of $rid:"
    echo
    ssh -o StrictHostKeyChecking=no admin@"$MIKROTIK_IP" <<EOF
ip arp print
EOF
    echo "------------------------------------------------------------------------------------------------------------------------"

    echo "IPs of $rid:"
    echo
    ssh -o StrictHostKeyChecking=no admin@"$MIKROTIK_IP" <<EOF
ip addr print
EOF
    echo "------------------------------------------------------------------------------------------------------------------------"

fi