#!/bin/bash
## Modified: 2021-04-14 
## Version: 0.1.4
## Purpose:  Bash Functions for Docker Enterprise Edition Tools 
## Requirements: unzip curl jq
## Author:   Michael Zervakis mzerv675@gmail.com

set -e
set -E

function catch_error () {
    trap '' ERR
    echo "Error: $@" >&2
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
        if [ "$char" = $'\x7f' ];  # backspace was pressed
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

function get_random () {
    # requires number of random characters
    [ -z "$1" ] && { ERROR="Invalid invocation without number of random characters"; return 1; }
    if grep -E -q '^[0-9]+$' <<< $1;
    then
        RANDOMCHARS=''
        while [ ${#RANDOMCHARS} -lt $1 ]
        do
            local CHAR=$(head -c 1 /dev/urandom | tr -dc 'a-zA-Z0-9')
            [ -n "$CHAR" ] && RANDOMCHARS="$RANDOMCHARS$CHAR"
        done
        return 0
    else
        ERROR="Invalid invocation without number of random characters"
        return 1
    fi
}

function get_secret () {
    NEWSECRET=''
    local SECRET_0=''
    local SECRET_1=''
    while [ -z "$NEWSECRET" ]
    do
        printf "New Passphrase: "
        get_input '\x2a'
        [ -z "$INPUT" ] && continue
        SECRET_0=$INPUT
        printf "Retype Passphrase: "
        get_input '\x2a'
        SECRET_1=$INPUT
        [ "$SECRET_0" = "$SECRET_1" ] && NEWSECRET=$SECRET_0 || echo "Passphrases do not match"
        unset INPUT
    done
    
    unset INPUT
}

function ucphost () {
    
    export UCP_HOST=''
    export UCP_PORT=''

    if [ -z "$1" ];
    then
        printf "UCP Hostname: "
        get_input
    else 
        INPUT="$1"
    fi

    # Input Validation
    if grep -E -q '^[a-zA-Z0-9-]+([.][a-zA-Z0-9-]+)*(:[0-9]+)?$' <<< $INPUT;
    then
        UCP_HOST=$(sed -r 's/^([a-zA-Z0-9-]+[a-zA-Z0-9.-]*)(:[0-9]+)?$/\1/' <<< $INPUT | tr '[A-Z]' '[a-z]')
        if grep -E -q '^[a-zA-Z0-9-]+[a-zA-Z0-9.-]*:[0-9]+$' <<< $INPUT;
        then
            UCP_PORT=$(sed -r 's/^([a-zA-Z0-9-]+[a-zA-Z0-9.-]*:)([0-9]+)$/\2/' <<< $INPUT)
        else
            UCP_PORT=443
        fi
        unset INPUT
        return 0
    else
        # if value was provided non interactively return error, otherwise allow user to retry
        [ -n "$1" ] && { ERROR="Invalid UCP Domain Name $1"; return 1;  }
        unset INPUT
        return 0
    fi
}

function ucphealth () {
    
    while [ -z "$UCP_HOST" ]
    do
        ucphost
        [ -z "$UCP_HOST" ] && echo "Invalid Hostname provided ex. ucp.domain.local:443"
    done

    ERROR="UCP at https://${UCP_HOST}:${UCP_PORT} is unreachable"
    HTTP_CODE=$(curl -x '' -k -s --connect-timeout 10 -w "%{http_code}\n" https://${UCP_HOST}:${UCP_PORT}/_ping -o /dev/null)
    
    [ $HTTP_CODE -ne 200 ] && { ERROR="UCP at https://${UCP_HOST}:${UCP_PORT} is unhealthy"; return 1; }
    return 0
}

function authtoken () {

    [ -n "$AUTHTOKEN" ] && return 0

    [ ! -x "$(command -v curl)" ] && { ERROR='curl is not installed.' ; return 1; }
    [ ! -x "$(command -v jq)" ] && { ERROR='jq is not installed.' ; return 1; }

    ucphealth

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
    ERROR="Request Failed to https://${UCP_HOST}:${UCP_PORT}/auth/login"
    REPLY=$(curl -x '' -s -k --connect-timeout 10 -d $POST https://${UCP_HOST}:${UCP_PORT}/auth/login)
    if [ -n "$REPLY"  ];
    then
        AUTHTOKEN=$(echo $REPLY | jq -r .auth_token)
        [ "$AUTHTOKEN" = 'null' ] && { unset AUTHTOKEN; ERROR="Failed login for User $USERNAME"; return 1; }
        unset REPLY
        return 0
    else
        ERROR="Invalid Response from https://${UCP_HOST}:${UCP_PORT}/auth/login"
        unset REPLY
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

    [ ! -x "$(command -v unzip)" ] && { ERROR='unzip is not installed.'; return 1; }

    if [ -f "${BUNDLE_PATH}/bundle.zip"  ];
    then
        SOURCE_PATH=$(pwd)
        ERROR="Failed to unzip ${BUNDLE_PATH}/bundle.zip"
        cd "$BUNDLE_PATH" && unzip -o -q bundle.zip
        cd "$SOURCE_PATH"
        return 0
    else
        ERROR="Bundle Zip not found in ${BUNDLE_PATH}"
        return 1
    fi
}

function createbundle () {
    # Download new client bundle
    [ ! -x "$(command -v curl)" ] && { ERROR='curl is not installed.' ; return 1; }

    bundlepath
    
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
    curl -x '' -s -k -H "Authorization: Bearer $AUTHTOKEN" https://${UCP_HOST}:${UCP_PORT}/api/clientbundle -o "$BUNDLE_PATH/bundle.zip"
    
    unzipbundle
    return 0
}

function verifybundle () {
    # Test if certificates exist and are valid
    [ -z "$BUNDLE_PATH" ] && bundlepath
    BUNDLEOK=1
    if [ -d "$BUNDLE_PATH" ];
    then
        # Test if Files Exist
        for FILE in kube.yml cert.pem key.pem ca.pem
        do
            [ ! -e "${BUNDLE_PATH}/${FILE}" ] && { echo "Bundle file $FILE missing"; BUNDLEOK=0; return 0; }
        done
        # Verify Cert
        local CAVERIFY=$(openssl verify -CAfile "${BUNDLE_PATH}/ca.pem" "${BUNDLE_PATH}/cert.pem")
        if grep -E -q ': OK$' <<< $CAVERIFY;
        then
            local KEYFINGER=$(openssl pkey -in "${BUNDLE_PATH}/key.pem" -pubout -outform pem | sha256sum)
            local CERTFINGER=$(openssl x509 -in "${BUNDLE_PATH}/cert.pem" -pubkey -noout -outform pem | sha256sum)
            [ "$KEYFINGER" != "$CERTFINGER" ] && { echo "Failed to verify client private key ${BUNDLE_PATH}/key.pem"; BUNDLEOK=0; }
        else
            echo "Failed to verify client certificate ${BUNDLE_PATH}/cert.pem"
            BUNDLEOK=0
        fi
    else
        BUNDLEOK=0
    fi
    return 0
}