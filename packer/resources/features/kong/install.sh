#!/bin/bash
#
# Downloads the Kong package and installs its dependencies
#
# This script must be run as root
set -e

echo "Installing Kong's dependencies"
# jq is not a dependency of Kong but it's useful when looking up Cassandra nodes at startup
apt-get -y install netcat lua5.1 openssl libpcre3 dnsmasq jq

echo "Waiting 10 seconds to settle down after installing dnsmasq"
sleep 10

ubuntu_codename=$(lsb_release -c -s)
echo "Downloading Kong package for $ubuntu_codename"
wget -qO /tmp/kong.deb "https://downloadkong.org/${ubuntu_codename}_all.deb"

echo "Installing Kong"
dpkg -i /tmp/kong.deb

echo "Setting up logrotate for Kong"
my_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp $my_directory/kong.logrotate /etc/logrotate.d/kong

