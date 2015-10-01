#!/bin/bash
set -e

# Install mongo server
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo "deb http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.0.list
apt-get update
apt-get install -y mongodb-org

# disable default mongod and delete any created files
service mongod stop
echo "manual" > /etc/init/mongod.override
rm -rf /var/lib/mongodb/*

echo "Installing helper script dependencies"
apt-get install -y ruby ruby-dev sysfsutils
gem install aws-sdk -v '~> 2'

# install script to disable transparent huge pages
install -m 755 ${SCRIPTPATH}/templates/disable-transparent-hugepages /etc/init.d/disable-transparent-hugepages
update-rc.d disable-transparent-hugepages defaults

# install OpsManager MMS and backup daemon
curl -L https://downloads.mongodb.com/on-prem-mms/deb/mongodb-mms_1.8.1.290-1_x86_64.deb -o /tmp/mongo-mms.deb
dpkg --install /tmp/mongo-mms.deb
curl -L https://downloads.mongodb.com/on-prem-mms/deb/mongodb-mms-backup-daemon_1.8.1.290-1_x86_64.deb -o /tmp/mongo-mms-backup-daemon.deb
dpkg --install /tmp/mongo-mms-backup-daemon.deb