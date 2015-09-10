#!/bin/bash
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
apt-get install -y ruby ruby-dev sysfsutils

#cp ${SCRIPTPATH}/mongodb.service /etc/systemd/system/mongodb.service

#service mongodb restart

# TODO: replace with bundler
echo "Installing Ruby gems for helper scripts"
gem install aws-sdk -v '~> 2'
gem install mongo -v '~> 2'
gem install bson -v '~> 3'

echo "Installing rsyslog config"
cat > /etc/rsyslog.d/31-mongo-scripts.conf <<EOF
local1.*    /var/log/mongodb/scripts.log
EOF
service rsyslog restart
