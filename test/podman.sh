#!/bin/bash

# prerequisites:
# - create dnsname enabled podman networks: 
#   podman network create site1 site2 loadbalancer
#   { "capabilities": { "aliases": true }, "domainName": "dns.podman", "type": "dnsname" }
# - also make sure the podman host does not override dns hostname in /etc/hosts

echo "Updating podman container image"
echo "==============================="
podman build -f Containerfile -t ubi8/ubi-ansible-demo:latest

echo "Create podman containers"
echo "========================"
echo -n "Starting container loadbalancer0...."
podman run --name=loadbalancer0 --network loadbalancer --systemd=true  --workdir /work -v $(pwd):/work:rw  -d localhost/ubi8/ubi-ansible-demo:latest /sbin/init
for zone in site1 site2 ; do
    echo "Site: ${zone}"
    while read node ; do
        echo -n "Starting container ${node}.... "
        podman run --name=${node} --network ${zone} --systemd=true  --workdir /work -v $(pwd):/work:rw  -d localhost/ubi8/ubi-ansible-demo:latest /sbin/init
        # makes loadbalancer visible in sites1 (https://github.com/containers/podman/issues/8399)
        sleep 2 && podman exec -t ${node} sed -ci "$ a $(cat /run/user/0/containers/cni/dnsname/loadbalancer/addnhosts)" /etc/hosts > /dev/null
    done < <( ansible-inventory -i ../scenario --list | jq -r ".${zone}.hosts[]")
done
podman network reload --all 2>&1 >/dev/null

echo "Provision containers"
echo "===================="
ANSIBLE_CONFIG=./ansible-podman.cfg ansible-playbook -e @../rhn-creds.yml -i ../scenario ../playbooks/all.yml "$@"
