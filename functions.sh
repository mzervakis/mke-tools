#!/bin/bash
## Modified: 2019-12-01 
## Version: 0.1.1
## Purpose:  Bash Functions for Docker Enterprise Edition Tools 
## Requirements: unzip curl jq
## Author:   Michael Zervakis mzerv675@gmail.com

set -e
set -E

function catch_error () {
    trap '' ERR
    echo "$@" >&2
    exit 1
}

trap 'catch_error $ERROR' ERR

function get_input () {
    # $1 argument expects masking character ex. '\x2a'
    local char=''
    INPUT=''
    while IFS= read -r -s -n1 char;
    do
        [ -z "$char" ] && { printf '\n'; break; } # ENTER pressed; output \n and break.
        if [ "$char" == $'\x7f' ];  # backspace was pressed
        then
            if [ -n "$INPUT" ];
            then
                # Remove last char from output variable.
                INPUT=${INPUT%?}
                # Erase to the left.
                printf '\b \b'
            fi
        else
            # Add typed char to output variable.
            INPUT+=$char
            [ -n "$1" ] && printf $1 || printf $char
        fi
    done
}

function ucphost () {
    
    printf "UCP Hostname: "
    export UCP_HOST=''
    export UCP_PORT=''
    get_input
    # Input Validation
    if grep -E -q '^[a-zA-Z0-9]+[a-zA-Z0-9.]*(:[0-9]+)?$' <<< $INPUT;
    then
        UCP_HOST=$(sed -r 's/^([a-zA-Z0-9]+[a-zA-Z0-9.]*)(:[0-9]+)?$/\1/' <<< $INPUT)
        if grep -E -q '^[a-zA-Z0-9]+[a-zA-Z0-9.]*:[0-9]+$' <<< $INPUT;
        then
            UCP_PORT=$(sed -r 's/^([a-zA-Z0-9]+[a-zA-Z0-9.]*:)([0-9]+)$/\2/' <<< $INPUT)
        else
            UCP_PORT=443
        fi
    fi
    unset INPUT
    return 0
}

function authtoken () {

    [ -n "$AUTHTOKEN" ] && return 0

    [ ! -x "$(command -v curl)" ] && { ERROR='curl is not installed.' ; return 1; }
    [ ! -x "$(command -v jq)" ] && { ERROR='jq is not installed.' ; return 1; }

    while [ -z "$UCP_HOST" ]
    do
        ucphost
        [ -z "$UCP_HOST" ] && echo "Invalid Hostname provided ex. ucp.domain.local:443"
    done
    
    ERROR="Failed to Connect to https://$UCP_HOST"
    curl -kIfs --connect-timeout 10 https://${UCP_HOST}:${UCP_PORT} -o /dev/null

    # Get Credentials
    local USERNAME=''
    while [ -z "$USERNAME" ]
    do
        printf "Username: "
        get_input
        USERNAME=$INPUT
    done

    local PASSWORD=''
    while [ -z "$PASSWORD" ]
    do
        printf "Password: "
        get_input '\x2a'
        PASSWORD=$INPUT
    done
    
    unset INPUT
    

    local POST="{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"
    ERROR="Failed to Connect to https://${UCP_HOST}:${UCP_PORT}/auth/login"
    local REPLY=$(curl -sk --connect-timeout 10 -d $POST https://${UCP_HOST}:${UCP_PORT}/auth/login)
    if [ -n "$REPLY"  ];
    then
        AUTHTOKEN=$(echo $REPLY | jq -r .auth_token)
        [ "$AUTHTOKEN" == 'null' ] && { unset AUTHTOKEN; ERROR="Failed login for User $USERNAME"; return 1; }
        return 0
    else
        ERROR="No Response from $UCP_HOST"
        return 1
    fi
}

function bundlepath () {
    
    while [ -z "$UCP_HOST" ]
    do
        ucphost
        [ -z "$UCP_HOST" ] && echo "Invalid Hostname provided ex. ucp.domain.local:443"
    done
    export BUNDLE_PATH=~/.ucp/$UCP_HOST
    return 0
}

function unzipbundle () {

    [ ! -x "$(command -v unzip)" ] && { ERROR='Error: unzip is not installed.'; return 1; }

    if [ -f ${BUNDLE_PATH}/bundle.zip  ];
    then
        SOURCE_PATH=$(pwd)
        ERROR="Failed to unzip ${BUNDLE_PATH}/bundle.zip"
        cd $BUNDLE_PATH && unzip -o -q bundle.zip
        cd $SOURCE_PATH
        return 0
    else
        ERROR="Bundle Zip not found in ${BUNDLE_PATH}"
        return 1
    fi
}

function createbundle () {

    [ ! -x "$(command -v curl)" ] && { ERROR='curl is not installed.' ; return 1; }

    bundlepath
    
    ERROR='Failed to generate bearer token'
    authtoken
    
    if [ -d "$BUNDLE_PATH" ];
    then
        ERROR="Directory ${BUNDLE_PATH} not empty"
        [ "$(ls -A ${BUNDLE_PATH})" ] && return 1
    else
        ERROR="Failed to create $BUNDLE_PATH"
        mkdir -p "$BUNDLE_PATH"
    fi
    
    ERROR="Failed to generate client bundle from https://${UCP_HOST}:${UCP_PORT}/api/clientbundle"
    curl -sk -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_HOST}:${UCP_PORT}/api/clientbundle -o $BUNDLE_PATH/bundle.zip
    
    unzipbundle
}
