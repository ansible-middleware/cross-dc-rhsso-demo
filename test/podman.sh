#!/bin/bash

# prerequisites:
# - create dnsname enabled podman networks: 
#   podman network create site1 site2 loadbalancer
#   { "capabilities": { "aliases": true }, "domainName": "dns.podman", "type": "dnsname" }
# - also make sure the podman host does not override dns hostname in /etc/hosts

IMAGE="ubi8/ubi-ansible-demo:latest"

#[ $(which jq) ] || { echo "Need jq installed to run this script"; exit -1 }

# Create network if not existing
NETWORKS=( loadbalancer site1 site2 )
for net in ${NETWORKS[@]}; do
    if ! $(podman network exists ${net}); then
        echo "Creating network ${net}"
	NETCONF=$(podman network create ${net})
	sed -i -e 's#"domainName": "dns.podman"#"domainName": "rhssocrossdc.com"#' ${NETCONF}
    fi
done

# Determine IP Address for Loadbalancer
echo "Determing IP Address for loadbalancer Container"
echo "==============================================="
MIN_SUBNET_ADDRESS=$(ipcalc $(podman network inspect loadbalancer | jq -r '.[] | .plugins[] | select(.type == "bridge").ipam.ranges[0][0].subnet') | grep "HostMin" | awk '{ print $2 }')
LOADBALANCER_IP=$(awk -F\. '{ print $1"."$2"."$3"."$4+1 }' <<< $MIN_SUBNET_ADDRESS )

echo "Updating podman container image"
echo "==============================="
podman build -f Containerfile -t ${IMAGE}

echo "Create podman containers"
echo "========================"
echo -n "Starting container loadbalancer0...."
podman run --replace --name=loadbalancer0 --security-opt=seccomp=unconfined -p 10080:80 -p 10443:443 --ip=$LOADBALANCER_IP \
           --network loadbalancer --dns-search rhssocrossdc.com --hostname loadbalancer0.rhssocrossdc.com --privileged \
	   --network-alias loadbalancer0 --systemd=true  --workdir /opt  -e TZ=CET --tz=Europe/Rome \
           --add-host=loadbalancer0:$LOADBALANCER_IP -d localhost/${IMAGE} /sbin/init
for zone in site1 site2 ; do
    echo "Site: ${zone}"
    while read node ; do
        echo -n "Starting container ${node}.... "
        podman run --replace --name=${node} --network ${zone} --security-opt=seccomp=unconfined --privileged \
	           --dns-search rhssocrossdc.com --hostname ${node}.rhssocrossdc.com \
		   --network-alias ${node} --systemd=true  --workdir /opt  -e TZ=CET --tz=Europe/Rome \
		   --add-host="loadbalancer0.rhssocrossdc.com loadbalancer0:$LOADBALANCER_IP" -d localhost/${IMAGE} /sbin/init
    done < <( ansible-inventory -i ../scenario --list | jq -r ".${zone}.hosts[]")
done
podman network reload --all 2>&1 >/dev/null

echo "Provision containers"
echo "===================="
ANSIBLE_CONFIG=./ansible-podman.cfg ansible-playbook -e @../rhn-creds.yml -i ../scenario ../playbooks/all.yml "$@"
