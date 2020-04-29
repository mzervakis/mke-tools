#!/bin/bash
## Modified: 2020-04-28 
## Version: 0.1.3
## Purpose:  UCP 3.2 Backup
## Requirements: functions.sh
## Author:   Michael Zervakis mzerv675@gmail.com

set -e
set -E

SCRIPT_PATH=$(dirname "${BASH_SOURCE[0]}")
[ ! -x "${SCRIPT_PATH}/functions.sh" ] && { echo "Failed to source ${SCRIPT_PATH}/functions.sh" >&2 ; exit 1;}
source "$SCRIPT_PATH/functions.sh"

### Example API invokation
# https://docs.docker.com/ee/admin/backup/back-up-ucp/#create-list-and-retrieve-ucp-backups-using-the-api

## FUNCTIONS

function backuppath () {
    
    BACKUPPATH=''
    
    if [ -z "$1" ];
    then
        printf "Backup Path: "
        get_input
    else 
        INPUT="$1"
    fi

    # Input Validation
    if grep -E -q '^/[^/\\]+(/[^/\\]*)*$' <<< $INPUT;
    then
        BACKUPPATH=$INPUT;
        unset INPUT
        return 0
    else
        # if value was provided non interactively return error, otherwise allow user to retry
        [ -n "$1" ] && { ERROR="Invalid backup path $1"; return 1;  }
        unset INPUT
        return 0
    fi
}

function getbackup () {
    if [ -n "$DOCKER_CERT_PATH" ] && [ $BUNDLEOK -eq 1  ];
    then
        ERROR="Failed to get backup status for ${BACKUPID}"
        BACKUP_DOC=$(curl -s --connect-timeout 10 --cacert ${BUNDLE_PATH}/ca.pem --cert ${BUNDLE_PATH}/cert.pem --key ${BUNDLE_PATH}/key.pem https://${UCP_HOST}:${UCP_PORT}/api/ucp/backup/${BACKUPID})
    else
        ERROR="Failed to get backup status for ${BACKUPID}"
        BACKUP_DOC=$(curl -s --connect-timeout 10 -k -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_HOST}:${UCP_PORT}/api/ucp/backup/${BACKUPID})
    fi    
}

FLAG_PASSPHRASE=0

## Arguments
if [ -n $1 ];
then 
    [ ! -x "$(command -v getopt)" ] && { echo 'Error: getopt is not installed.' >&2; exit 1; }
    ARGS=$(getopt -o u:p:ve -l ucp: -l version -l path -l encrypt -- $@)
    eval set -- "$ARGS"
    while true; do
    case "$1" in
    -v)
        echo "Version: 0.1.3"
        exit 0        
        ;;
    --version)
        echo "Version: 0.1.3"
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
    -p)
        shift
        backuppath "$1"
        ;;
    --path)
        shift
        backuppath "$1"
        ;;
    -e)
        FLAG_PASSPHRASE=1
        ;;
    --encrypt)
        FLAG_PASSPHRASE=1
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
fi

## MAIN

while [ -z "$BACKUPPATH" ]
do
    backuppath
    [ -z "$BACKUPPATH" ] && echo "Invalid Path provided ex. /backup"
done


TIMESTAMP=$(date +%Y-%m-%dT%H.%M.%S)

get_random 4

FILENAME="ucp-${TIMESTAMP}-${RANDOMCHARS}"

if [ $FLAG_PASSPHRASE -eq 1 ];
then
    get_secret
    POST_DOC="{\"passphrase\": \"${NEWSECRET}\", \"includeLogs\": false, \"filename\": \"${FILENAME}.tar\", \"logFileName\": \"${FILENAME}.log\", \"hostPath\": \"${BACKUPPATH}\"}"
else
    POST_DOC="{\"noPassphrase\": true, \"includeLogs\": false, \"filename\": \"${FILENAME}.tar\", \"logFileName\": \"${FILENAME}.log\", \"hostPath\": \"${BACKUPPATH}\"}"
fi

# Check if client bundle is configured
[ -n "$DOCKER_CERT_PATH" ] && verifybundle

if [ -n "$DOCKER_CERT_PATH" ] && [ $BUNDLEOK -eq 1  ];
then
    echo "Using Client Bundle in ${BUNDLE_PATH}"
    ERROR="Failed to Start Backup"
    BACKUP_RESULT=$(curl -s --connect-timeout 10 --cacert ${BUNDLE_PATH}/ca.pem --cert ${BUNDLE_PATH}/cert.pem --key ${BUNDLE_PATH}/key.pem -H "Content-Type: application/json" https://${UCP_HOST}:${UCP_PORT}/api/ucp/backup --data "$POST_DOC")
else
    # If client bundle is missing request authentication token
    authtoken
    ERROR="Failed to Start Backup"
    BACKUP_RESULT=$(curl -s --connect-timeout 10 -k -H "Authorization: Bearer $AUTHTOKEN" -H "Content-Type: application/json" https://${UCP_HOST}:${UCP_PORT}/api/ucp/backup --data "$POST_DOC")
fi

# Result {"backupId":"76f4db71-d556-41cf-bf10-a3181234515e"}

if [ -n "$BACKUP_RESULT" ];
then
    BACKUPID=$(echo $BACKUP_RESULT | jq -r .backupId)
    [ "$BACKUPID" = 'null' ] && { echo "Backup Failed $BACKUP_RESULT" >&2; exit 1; }
    echo "Started Backup Job ID: $BACKUPID, File: ${BACKUPPATH}/${FILENAME}.tar"
else
    echo "Request Failed No Response" >&2; exit 1;
fi

# Get Backup Status
echo "Waiting Backup Job ID: ${BACKUPID} to finish"
getbackup
BACKUPSTATE=$(jq -r .backupState <<<$BACKUP_DOC)

while [ "$BACKUPSTATE" = "IN_PROGRESS" ]
do
    sleep 3
    getbackup
    BACKUPSTATE=$(jq -r .backupState <<<$BACKUP_DOC)
done

if [ "$BACKUPSTATE" = "FAILED" ];
then
   FAILMESSAGE=$(jq -r .shortError <<<$BACKUP_DOC)
   echo "Failed Backup Job ID: $BACKUPID, Reason: $FAILMESSAGE" >&2
   exit 1
elif [ "$BACKUPSTATE" = "SUCCESS" ];
then
   NODELOCATION=$(jq -r .nodeLocation <<<$BACKUP_DOC)
   echo "Successful Backup Job ID: $BACKUPID, File: ${BACKUPPATH}/${FILENAME}.tar, Node: $NODELOCATION"
else
   echo "Unknown Status for Backup Job ID:$BACKUPID, $BACKUP_DOC"
   exit 1
fi
