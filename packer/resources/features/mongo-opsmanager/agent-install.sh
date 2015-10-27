#!/bin/bash
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
apt-get install -y ruby ruby-dev sysfsutils

# TODO: replace with bundler
echo "Installing Ruby gems for helper scripts"
gem install aws-sdk -v '~> 2'
gem install mongo -v '~> 2'
gem install bson -v '~> 3'
gem install httparty

echo "Installing rsyslog config"
cat > /etc/rsyslog.d/31-mongo-scripts.conf <<EOF
local1.*    /var/log/mongodb-scripts/scripts.log
EOF
service rsyslog restart

# install script to disable transparent huge pages
install -m 755 ${SCRIPTPATH}/templates/disable-transparent-hugepages /etc/init.d/disable-transparent-hugepages
update-rc.d disable-transparent-hugepages defaults

# install script to set readahead
install -m 755 ${SCRIPTPATH}/templates/set-readahead /etc/init.d/set-readahead
update-rc.d set-readahead defaults

echo "net.ipv4.tcp_keepalive_time = 300" > /etc/sysctl.d/71-tcp-keepalive.conf