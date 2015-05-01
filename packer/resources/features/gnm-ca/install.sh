#!/bin/bash
# This script must be run as root
# Install GNM CA in the OS and JVM - you *probably* only want to do this in
# pre-prod environments to reduce the impact of the mis-use of the GNM root CA.
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
CERTIFICATES=${SCRIPTPATH}/*.crt

# Make sure ca-certificates-java is installed
if ! (dpkg -s ca-certificates-java 2> /dev/null > /dev/null); then
    sudo apt-get install -y ca-certificates-java
fi

mkdir -p /usr/local/share/ca-certificates/GNM
cp ${CERTIFICATES} /usr/local/share/ca-certificates/GNM

update-ca-certificates
