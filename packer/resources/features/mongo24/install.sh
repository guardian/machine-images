#!/bin/bash
# Install MongoDB 2.4

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' > /etc/apt/sources.list.d/mongodb.list
apt-get update
apt-get install mongodb-10gen=2.4.9 ruby sysfsutils

gem install aws-sdk -v '<2'
gem install mongo -v '<2'
gem install bson_ext -v '<2'

cp ${SCRIPTPATH}/mongodb.service /etc/systemd/system/mongodb.service

systemctl start mongodb
