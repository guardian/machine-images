#!/bin/bash
# this is run as root

function new_section {
  echo
  echo $(date +"%F %T") $1
  echo "----------------------------------------------------------------------------------------"
}

set -e
mkdir -p /opt
cp -R /tmp/features /opt/

## Update index and install packages
new_section "Configuring extra repositories"
add-apt-repository "deb http://eu-west-1.ec2.archive.ubuntu.com/ubuntu/ wily universe multiverse"
add-apt-repository "deb http://eu-west-1.ec2.archive.ubuntu.com/ubuntu/ wily main restricted"
add-apt-repository "deb http://eu-west-1.ec2.archive.ubuntu.com/ubuntu/ wily-updates universe multiverse"
# sometimes apt-get update doesn't see the changes here, try sleeping for a moment
sleep 1

new_section "Updating packages"
apt-get update
apt-get --yes upgrade

## Install packages
new_section "Installing required packages"
apt-get --yes --force-yes install \
  git wget language-pack-en build-essential python-setuptools \
  openjdk-8-jre-headless openjdk-8-jdk cloud-guest-utils jq \
  ntp unzip python3-pip

## Workaround for Debian Java packaging bug
## See:
## https://github.com/guardian/status-app/blob/play-2.4/cloud-formation/status-app.json#L159
## https://bugs.launchpad.net/ubuntu/+source/ca-certificates-java/+bug/1396760
## https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=775775
/var/lib/dpkg/info/ca-certificates-java.postinst configure

## Install AWSCLI tools
new_section "Installing latest AWSCLI"
pip3 install awscli

## Install AWS-CFN tools
new_section "Installing AWS-CFN tools"
wget -P /tmp https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
mkdir -p /tmp/aws-cfn-bootstrap-latest
tar xvfz /tmp/aws-cfn-bootstrap-latest.tar.gz --strip-components=1 -C /tmp/aws-cfn-bootstrap-latest
# This seems to frequently fail, so run in a short loop
LIMIT=3
COUNT=1
while [ $COUNT -le $LIMIT ]; do
  echo "Attempting to install cfn-init ($COUNT/$LIMIT)..."
  if easy_install /tmp/aws-cfn-bootstrap-latest/; then
    rm -fr /tmp/aws-cfn-bootstrap-latest
    break
  else
    let COUNT=COUNT+1
  fi
done

## Configure Amazon's NTP servers
new_section "Configuring NTP"
sed -i s/ubuntu.pool.ntp.org/amazon.pool.ntp.org/ /etc/ntp.conf
# TODO: If building a PV based image we should change the sysctl to disable the wallclock

## Setup network adapter

new_section "Configuring enhanced networking (ixgbevf)"
/opt/features/ixgbevf/install.sh

## Ensure we don't swap unnecessarily
echo "vm.overcommit_memory=1" > /etc/sysctl.d/70-vm-overcommit.conf

new_section "Configuring locale"
locale-gen en_GB.UTF-8

