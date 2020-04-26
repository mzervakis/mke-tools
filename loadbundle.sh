#!/bin/bash
## Modified: 2020-04-26 
## Version: 0.1.2
## Purpose:  Start New Shell configured from Client Bundle
## Requirements: functions.sh
## Author:   Michael Zervakis mzerv675@gmail.com

set -e
set -E

[ ! -x "$(command -v kubectl)" ] && { echo 'Error: kubectl is not installed.' >&2; exit 1; }
[ ! -x "$(command -v docker)" ] && { echo 'Error: docker-cli is not installed.' >&2; exit 1; }

SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")
[ ! -x "${SCRIPT_PATH}/functions.sh" ] && { echo "Failed to source ${SCRIPT_PATH}/functions.sh" >&2 ; exit 1;}
source "$SCRIPT_PATH/functions.sh"

if [ -n $1 ];
then 
    ARGS=$(getopt -o u:v -l ucp: -l version -- $@)
    eval set -- "$ARGS"
    while true; do
    case "$1" in
    -v)
        echo "Version: 0.1.2"
        exit 0        
        ;;
    --version)
        echo "Version: 0.1.2"
        exit 0
        ;;
    -u)
        shift
        ucphost "$1"
        ;;
    --ucp)
        shift
        ucphost "$1"
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
fi

bundlepath

BUNDLEOK=1

if [ -d "$BUNDLE_PATH" ];
then
    for FILE in kube.yml cert.pem key.pem ca.pem
    do
        [ ! -e "$BUNDLE_PATH/$FILE" ] && { echo "$FILE missing"; BUNDLEOK=0; break; }
    done
else
    BUNDLEOK=0
fi

if [ $BUNDLEOK -eq 0 ];
then
    if [ -f "$BUNDLE_PATH/bundle.zip" ];
    then
        unzipbundle
    else
        createbundle
    fi
fi
unset BUNDLEOK

# kubectl Env
unset KUBECONFIG
export UCP_USER=$(openssl x509 -in "${BUNDLE_PATH}/cert.pem" -text -noout | egrep 'Subject.*CN' | sed -e 's/.*CN[ ]*=[ ]*//')
kubectl config set-cluster ucp_${UCP_HOST}:6443_${UCP_USER} --server https://${UCP_HOST}:6443 --certificate-authority "${BUNDLE_PATH}/ca.pem" --embed-certs
kubectl config set-credentials ucp_${UCP_HOST}:6443_${UCP_USER} --client-key "${BUNDLE_PATH}/key.pem" --client-certificate "${BUNDLE_PATH}/cert.pem" --embed-certs
kubectl config set-context ucp_${UCP_HOST}:6443_${UCP_USER} --user ucp_${UCP_HOST}:6443_${UCP_USER} --cluster ucp_${UCP_HOST}:6443_${UCP_USER}
export KUBECONFIG="${BUNDLE_PATH}/kube.yml"
# docker Env
export DOCKER_TLS_VERIFY=1
export COMPOSE_TLS_VERSION=TLSv1_2
export DOCKER_CERT_PATH="${BUNDLE_PATH}"
export DOCKER_HOST=tcp://${UCP_HOST}:${UCP_PORT}
# etcdctl Env
export ETCDCTL_API=3
export ETCDCTL_KEY="${BUNDLE_PATH}/key.pem"
export ETCDCTL_CACERT="${BUNDLE_PATH}/ca.pem"
export ETCDCTL_CERT="${BUNDLE_PATH}/cert.pem"
export ETCDCTL_ENDPOINTS=https://${UCP_HOST}:12378
# calicoctl Env
export ETCD_ENDPOINTS=${UCP_HOST}:12378
export ETCD_KEY_FILE="${BUNDLE_PATH}/key.pem"
export ETCD_CA_CERT_FILE="${BUNDLE_PATH}/ca.pem"
export ETCD_CERT_FILE="${BUNDLE_PATH}/cert.pem"

# bash rc
RCFILE=$(mktemp)
echo 'export PS1="\[\e]0;\u@\h: \w\a\]${UCP_USER}@${UCP_HOST}:\w\$"' > $RCFILE
echo 'shopt -s checkwinsize' >> $RCFILE
if ! shopt -oq posix ;
then
    if [ -f /usr/share/bash-completion/bash_completion ];
    then
        echo "source /usr/share/bash-completion/bash_completion" >> $RCFILE
    elif [ -f /etc/bash_completion ]; 
    then
        echo "source /etc/bash_completion" >> $RCFILE
    fi
fi
kubectl completion bash >> $RCFILE
echo "rm -f $RCFILE" >> $RCFILE

# start bash
exec bash --rcfile $RCFILE -i