#!/bin/bash

# 20200707, jtingiris

# i.e. servicePrincipal.sh # all arguments are optional & will be derived from current az login

function aborting() {
    echo
    echo "aborting ... $@"
    echo
    exit 1
}

function usage() {
    echo
    echo "usage: $0 [-r <service principle roles>] [-s <subscription id>] [-n <service principal name>]"
    echo
    exit 2
}

set -e

while getopts "hn:r:s:" opt; do
    case $opt in
        h)
            usage
            ;;
        n)
            spName=$OPTARG # optional service principle name
            ;;
        r)
            spRoles=$OPTARG # coma seperated roles
            ;;
        s)
            subscriptionId=$OPTARG # optional subscription ID
            ;;
        *)
            usage
            ;;
    esac
done

# if not installed then install jq
if ! command -v jq &> /dev/null
then
    echo "jq command not found. attempting to download jq binary"
    pth=$(pwd)
    export PATH=$PATH:$pth
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o jq
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64 -o jq
    else
        echo "Unsupported OS type. Exiting..."
        exit 1
    fi
    chmod +x jq
fi

if [ -z $spRoles ]; then
    spRoles="Contributor,User Access Administrator"
fi

IFS=','; rolesArr=($spRoles); unset IFS;
role1="${rolesArr[0]}"

if [ -z $subscriptionId ]; then
    subscriptionId=$( az account show -o json | jq -r '.id' )
fi

if [ -z $subscriptionId ]; then
    aborting "can't determine subscription id"
fi

if [ -z $spName ]; then
    spName=cp4d-sp
fi

spHttpName=http://$spName

echo "spName     = $spName" > ${spName}-info.txt
echo "spHttpName = $spHttpName" >> ${spName}-info.txt
echo "spRoles    = $spRoles" >> ${spName}-info.txt
echo >> ${spName}-info.txt

spData="$(az ad sp list --all | jq -r ".[] | select(.displayName==\"${spName}\")" 2> /dev/null)"
if [ -z "${spData}" ]; then
    echo "Creating service principle ..."
    #  SET DISPLAY NAME SO IT SHOWS UP IN THE AZURE PORTAL!!! i.e. --name ServicePrincipalName
    echo "az ad sp create-for-rbac --role=\"$role1\" --scopes=\"/subscriptions/$subscriptionId\" --name \"$spHttpName\""
    spJson=$(az ad sp create-for-rbac --role="$role1" --scopes="/subscriptions/$subscriptionId" --name "$spHttpName")
    aadClientSecret=$(echo $spJson | jq -r '.password')
    echo "$aadClientSecret" > ${spName}-secret.txt
else
    echo "Found existing service principle ..."
    spJson="${spData}"
    if [ -f ${spName}-secret.txt ]; then
        aadClientSecret=$(cat ${spName}-secret.txt)
    else
        if [ -f secrets/${spName}-secret.txt ]; then
            aadClientSecret=$(cat secrets/${spName}-secret.txt)
        else
            if [ -f ../secrets/${spName}-secret.txt ]; then
                aadClientSecret=$(cat ../secrets/${spName}-secret.txt)
            fi
        fi
    fi
fi

aadClientId=$(echo $spJson | jq -r '.appId')

echo >> ${spName}-info.txt
echo "aadClientId        = $aadClientId" >> ${spName}-info.txt

if [ -z "${aadClientSecret}" ]; then
    aborting "failed to find client secret"
fi

echo "aadClientSecret    = $aadClientSecret" >> ${spName}-info.txt

objectId=$( az ad sp list --filter "appId eq '$aadClientId'" | jq '.[0].objectId' -r )
echo "objectId           = $objectId" >> ${spName}-info.txt
echo >> ${spName}-info.txt

cat ${spName}-info.txt

if [ -z "${spData}" ]; then
    # assign roles 
    for role in "${rolesArr[@]}"
    do
        echo "Assigning role $role ..."
        echo
        az role assignment create --role "$role" --assignee $spHttpName
        echo
        #az role assignment create --role "$role" --assignee-object-id $objectId # doing it this way triggers a bug; --assignee-object-id gets its wires crossed ... READ THE DOCS; it bypasses the Graph API ... if other Contributors exist then it improperly assigns the roles to them, *NOT* the sp created previously, even though the $objectId is correct (and the output of --assignee-object-id is clearly wrong)
    done
fi

az role assignment list -o table

echo

# az ad sp delete --id $spHttpName
