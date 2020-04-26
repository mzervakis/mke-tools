# docker-ee-tools
Set of Bash shell scripts for using and administering Universal Control Plane and Kubernetes

## loadbundle.sh

Downloads Client Bundle and configures environment in a new interactive shell.

### Usage
Download loadbundle.sh and functions.sh in ~/bin and mark them as executable.

Simply run loadbundle.sh and provide UCP domain name and your UCP credentials.

To provide UCP domain name non-interactively ucp the -u option ex. loadbundle.sh -u ucp.example.com:8443

Client Bundle is stored in ~/.ucp

If UPC is using a non standard TLS port provide UCP domain name with the custom port ex. ucp.example.com:8443