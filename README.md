# cross-dc-rhsso-demo

Cross-Datacenter Replication mode lets you run Red Hat Single Sign-On in a cluster across multiple data centers, most typically using data center sites that are in different geographic regions. When using this mode, each data center will have its own cluster of Red Hat Single Sign-On servers.

This repository contains a reference configuration which can deploy two clusters of RH SSO instances, backed by a distributed bi-partitioned cluster of RH Datagrid instances.
For the sake of the demo, it also contains playbooks to deploy a loadbalancer (JBCS) in front of the scenario, and a highly-available database (mariadb with galera) on the backend.
Both RHSSO and RHDATAGRID clusters use jgroups JDBC_PING to advertise to each other; while RHSSO advertise to JBSC using mod_cluster.

The final architecture looks like:

![Architecture diagram](./scenario.png)


## Prerequisites

* rhel 8.4 with registered subscription
* ansible 2.9 / python 3.9
* `ansible-galaxy collection install -r requirements.yml`
* python3-netaddr installed on the controller host `dnf install python3-netaddr`
* a minimum of 9 (or possibly 12) instances for the whole production-like scenario


## Running in podman

_This configuration is for development and evaluation purposes only._


#### Prerequisites

To run the demo in podman containers, you will also need the following packages to be installed on the controller:

```
$ dnf install podman-plugins jq
```

Other requirements for running in podman are:
* a resonable amount of system memory ( >= 8GB )
* being able to run privileged containers
* and dnsname plugin being available for podman external-networks (installed with podman-plugins package above)
* large max number of threads for user: `echo 350000 > /proc/sys/kernel/threads-max`

The `test/` directory contains a Containerfile definition and a shell script to execute the full CrossDC scenario on podman containers; the script
will take care of building the images.

The host running podman _must_ be a registered RHEL8.4+ for building the demo image, or be a registered system using the dnf-subscription-manager-plugin,
so that subscription-manager runs in "container mode" inside container images.


#### Steps

1. Create a var-file containing your RHN credentials:
```
$ cat rhn-creds.yml
rhn_username: '<username>'
rhn_password: '<password>'
```

2. Run the podman.sh script:
```
cd test/
./podman.sh
```

The script will setup all necessary podman networks and containers, and perform the playbook execution via ansible.


#### Troubleshooting

* services report `OutOfMemoryException`

Sometimes java reports this stacktrace when the JVM is unable to start new threads; check your `/proc/sys/kernel/threads-max` 
and try to increase the limit. This is more likely to happen if you run in an X user session with many other applications open.
If the memory is exhausted, not much can be done, we suggest to run the stripped-down molecule scenario instead.

* SElinux alerts or errors

When the script runs podman commands, you may encounter SElinux forbidding ioctls on overlay files for the current users.
Set SElinux to permissive and create a policy to allow access.


## Running on baremetal/virtualized/cloud

1. Prepare your resources so that:
  - you have three bridged networks/vpcs; refer to the firewall configuration in the playbooks for security-group configuration
  - you have one instance on the first network (loadbalancer0), 6 and 5 instances on the other networks (site1 and site2 nodes); this can be reduced to 4 and 4 by aliasing the RHSSO nodes with the mariadb database nodes.
  - name resolution across the networks works

2. Create a var-file containing your RHN credentials:
```
$ cat rhn-creds.yml
rhn_username: '<username>'
rhn_password: '<password>'
```

3. Execute the main play:
```
ansible-playbook -e @rhn-creds.yml -i scenario playbooks/all.yml
```


## Running the molecule test scenarios

Two molecule scenarios are provided for developemnt and testing with reduced hardware requirements. 
The scenarios use centos:8 as base image, and can only be used for deploying keycloak/infinispan upstream projects.

* `molecule/default`: scenario based on podman driver, using 3 infinispan, 3 keycloaks and 2 mariadb nodes, no loadbalancer.
* `molecule/docker`: scenario based on docker driver, using 4 infinispan, 2 rhsso and 2 mariadb nodes, no loadbalancer.


## Security considerations

* The playbook deploys certificates signed by a self-signed test CA from the certificates role for SSO/JDG TLS connectivity on the HotRod protocol.
* Datagrid cluster communication is not encrypted; encryption will be added when configurable in the infinispan collection


## License

Apache License v2.0 or later

See [LICENCE](LICENSE) to view the full text.


## Authors

* Guido Grazioli <ggraziol@redhat.com>


## Credits

* The mariadb role is liberally taken from the galera-mariadb-cluster role.

