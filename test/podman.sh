#!/bin/bash

# prerequisites:
# - create dnsname enabled podman networks: 
#   podman network create site1 site2 loadbalancer
#   { "capabilities": { "aliases": true }, "domainName": "dns.podman", "type": "dnsname" }
# - also make sure the podman host does not override dns hostname in /etc/hosts

# Determine IP Address for Loadbalancer
echo "Determing IP Address for loadbalancer Container"
echo "==============================="
MIN_SUBNET_ADDRESS=$(ipcalc $(podman network inspect loadbalancer | jq -r '.[] | .plugins[] | select(.type == "bridge").ipam.ranges[0][0].subnet') | grep "HostMin" | awk '{ print $2 }')
LOADBALANCER_IP=$(awk -F\. '{ print $1"."$2"."$3"."$4+1 }' <<< $MIN_SUBNET_ADDRESS )

echo "Updating podman container image"
echo "==============================="
podman build -f Containerfile -t ubi8/ubi-ansible-demo:latest

echo "Create podman containers"
echo "========================"
echo -n "Starting container loadbalancer0...."
podman run --name=loadbalancer0 -p 80:80 -p 443:443 --ip=$LOADBALANCER_IP --network loadbalancer --systemd=true  --workdir /work -v $(pwd):/work:rw --add-host=loadbalancer0:$LOADBALANCER_IP -d localhost/ubi8/ubi-ansible-demo:latest /sbin/init
for zone in site1 site2 ; do
    echo "Site: ${zone}"
    while read node ; do
        echo -n "Starting container ${node}.... "
        podman run --name=${node} --network ${zone} --systemd=true  --workdir /work -v $(pwd):/work:rw  -d localhost/ubi8/ubi-ansible-demo:latest /sbin/init
    done < <( ansible-inventory -i ../scenario --list | jq -r ".${zone}.hosts[]")
done
podman network reload --all 2>&1 >/dev/null

echo "Provision containers"
echo "===================="
ANSIBLE_CONFIG=./ansible-podman.cfg ansible-playbook -e @../rhn-creds.yml -i ../scenario ../playbooks/all.yml "$@"
