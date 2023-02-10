# Mirantis Kubernetes Engine
Set of Bash shell scripts for using and administering Universal Control Plane and Kubernetes

## loadbundle.sh

Downloads Client Bundle and configures environment in a new interactive shell.

### Usage
Download loadbundle.sh and functions.sh in ~/bin and mark them as executable.

Simply run loadbundle.sh and provide MKE FQDN and your MKE credentials.

To provide MKE FQDN non-interactively use the -H option ex. loadbundle.sh -H mke.example.com:8443

Client Bundle is stored in ~/.mke

If MKE is using a non standard TLS port provide MKE FQDN with the custom port ex. ucp.example.com:8443

## mkebackup.sh

Backup MKE using the REST API.

### Usage
Download mkebackup.sh and functions.sh in ~/bin and mark them as executable.

If Client Bundle is configured mkebackup.sh will use TLS auth, otherwise it will request a new Bearer Token interactively 

mkebackup.sh -H mke.example.com:443 -p /mnt/backup

or 

mkebackup.sh -H mke.example.com:443 -p /mnt/backup -e

for encrypted backup
