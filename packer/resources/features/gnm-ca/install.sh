#!/bin/bash
# This script must be run as root
# Install GNM CA in the OS and JVM - you *probably* only want to do this in
# pre-prod environments to reduce the impact of the mis-use of the GNM root CA.
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

mkdir -p /usr/local/share/ca-certificates/GNM
cp ${SCRIPTPATH}/*.crt /usr/local/share/ca-certificates/GNM

update-ca-certificates
