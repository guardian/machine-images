#!/bin/bash
# this is run as root

function new_section {
  echo
  echo $(date +"%F %T") $1
  echo "----------------------------------------------------------------------------------------"
}

set -e
## Update index and install packages
new_section "Configuring extra repositories"
add-apt-repository "deb http://eu-west-1.ec2.archive.ubuntu.com/ubuntu/ vivid universe"
# sometimes apt-get update doesn't see the changes here, try sleeping for a moment
sleep 1

new_section "Updating package lists"
apt-get update

## Install Java 8 packages
new_section "Installing required packages"
apt-get --yes --force-yes install \
  openjdk-8-jre-headless openjdk-8-jdk

## Uninstall Java 7 packages
new_section "Uninstalling Java 7"
apt-get --yes --force-yes remove \
  openjdk-7-jre-headless openjdk-7-jdk
