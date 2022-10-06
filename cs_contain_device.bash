#!/bin/bash
#shellcheck shell=bash


#Requriments check
if ! ( jq --version > /dev/null ); then
    echo "jq was not found on this host. This package is a requriment this script to run. Please install jq package."
    exit 1
fi

#bearer authentication
AWSSECRET=$(aws secretsmanager get-secret-value --secret-id Crowdstrike_API_Key --region us-west-2 | jq -r .SecretString | jq .)
API_CLIENT_ID="$(echo "${AWSSECRET}" | jq -r .API_CLIENT_ID)"
API_SECRET="$(echo "${AWSSECRET}" | jq -r .API_SECRET)"

# These 2 group IDs are the only ones that are the script can contain. You cannot see these in the crowdstrike UI the must be pulled via the api.
WindowsHostGroupID=YOUR_GROUP_ID_HERE
MacHostGroupID=YOUR_GROUP_ID_HERE

ACCESS_TOKEN="$(curl -s  https://api.crowdstrike.com/oauth2/token -POST -d "client_id=$API_CLIENT_ID" -d "client_secret=$API_SECRET" | jq -r '.access_token')"

# user prompt for serial
read -r -p "Provide host serial number you would like to process: " SERIAL_NUMBER

SERIAL_NUMBER=$(echo "$SERIAL_NUMBER" | tr '[:lower:]' '[:upper:]')

RESOURCE_ID="$(curl -s -X GET "https://api.crowdstrike.com/devices/queries/devices/v1?offset=0&limit=1&filter=serial_number%3A%22${SERIAL_NUMBER}%22" -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.resources[]')"

HostInfoJson=$(curl -s -X GET "https://api.crowdstrike.com/devices/entities/devices/v1?ids=${RESOURCE_ID}" -H  "accept: application/json" -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.resources[]')


HostData=$( echo "$HostInfoJson" |jq -rc '.hostname, .serial_number, .platform_name, .os_build, .last_seen' )
HostGroups=$(echo "$HostInfoJson" |jq -r '.groups' | jq -r '.[]')


resultsQuestion() {
    echo ""
    echo "Please confirm this is the host you would like to process."
    echo "Hostname: ${1}"
    echo "Serial Number: ${2}"
    echo "Platform: ${3}"
    echo "OS Build: ${4}"
    echo "Last Seen: ${5}"
    while true; do
        read -rp "Is this correct? " yn
        case $yn in
            [Yy]* ) ProcessChoice="yes"; break;;
            [Nn]* ) ProcessChoice="no"; echo "User opted to not continue with selected host, exiting."; exit 0;;
            * ) echo "Please anwser yes or no.";;
        esac
    done
    clear
    while true; do
        echo "Would you like to contain host (Add network isolation) or lift containment?"
        read -rp "Answer with the word \"contain\" or \"lift\": " liftcontain
        case $liftcontain in
            [Cc]ontain ) ContainChoice="yes"; break;;
            [Ll]ift ) ContainChoice="no"; break;;
            * ) echo "Please anwser with \"contain\" or \"lift\".";;
        esac
    done
}

badGroupNotice() {
    clear
    echo "Host provided was not found in Windows desktop or Mac groups. In order to prevent possible damage caused by locking the wrong device we cannot proceed. Please contact the IT Admin team for more info."
    echo "Information about host ID for troubleshooting:"
    echo "Hostname: ${1}"
    echo "Serial Number: ${2}"
    echo "Platform: ${3}"
    echo "OS Build: ${4}"
    echo "Last Seen: ${5}"
    echo "Host Groups:"
    echo "$HostGroups"
    echo ""
}

#actual work starts here.
# These checks are used to prevent techs from locking out anything outsdie of the windows and mac desktop groups provided at the start of this script.
if ( echo "$HostGroups" | grep "$MacHostGroupID" > /dev/null ); then
    DeviceGroup="Mac"
    echo ""
    echo "Device Group: ${DeviceGroup}"
elif ( echo "$HostGroups" | grep "$WindowsHostGroupID" > /dev/null ); then
    DeviceGroup="Windows"
    echo ""
    echo "Device Group:: ${DeviceGroup}"
else
    DeviceGroup="Unknown"
    echo ""
    echo "Device Group: ${DeviceGroup}"
fi

if [[ -n "$RESOURCE_ID" ]]; then
    resultsQuestion ${HostData}
    if [[ "$DeviceGroup" == "Unknown" ]]; then
        badGroupNotice ${HostData}
        exit 1
    else
        if [[ "$ProcessChoice" == yes ]]; then
            if [[ "$ContainChoice" == yes ]]; then
                echo ""
                echo "Attempting to contain device. Results:"
                curl -X POST "https://api.crowdstrike.com/devices/entities/devices-actions/v2?action_name=contain" -H "accept: application/json" -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d "{  \"action_parameters\": [    {      \"name\": \"string\",      \"value\": \"string\"    }  ],  \"ids\": [    \"${RESOURCE_ID}\"  ]}"
            else
                echo ""
                echo "Attempting to lift containment from host. Results:"
                curl -X POST "https://api.crowdstrike.com/devices/entities/devices-actions/v2?action_name=lift_containment" -H "accept: application/json" -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d "{  \"action_parameters\": [    {      \"name\": \"string\",      \"value\": \"string\"    }  ],  \"ids\": [    \"${RESOURCE_ID}\"  ]}"
            fi
        else
            echo "User opted to not continue with selected host, exiting."
        fi
    fi
else
    echo ""
    echo "No host was found based on provided serial number. Verify the serial number you entered is correct."
    echo ""
    echo "Pro tip: If it's a mac serial number number and you have an S as the first chracter remove the S. It's just an indicator that it's a serial number."
    exit 1
fi