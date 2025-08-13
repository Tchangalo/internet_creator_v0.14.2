#!/bin/bash

provider=$1
first_router=$2
last_router=$3

C='\033[0;94m'
R='\033[91m'
NC='\033[0m'

if [[ $# -ne 3 ]]; then
  echo -e "${R}Error: At least one variable is empty!${NC}"
  exit 1
fi

for i in $(seq $first_router $last_router); do
  if [[ ${#i} -eq 1 ]]; then
      VM_ID="${provider}0${provider}00$i"
  else
      VM_ID="${provider}0${provider}0$i"
  fi
  sudo qm shutdown $VM_ID
done