#!/bin/bash
#
# Downloads the Kong package and installs its dependencies
#
# This script must be run as root
set -e

echo "Installing Kong's dependencies"
apt-get -y install netcat lua5.1 openssl libpcre3 dnsmasq

echo "Waiting 10 seconds to settle down after installing dnsmasq"
sleep 10

ubuntu_codename=$(lsb_release -c -s)
echo "Downloading Kong package for $ubuntu_codename"
wget -qO /tmp/kong.deb "https://downloadkong.org/${ubuntu_codename}_all.deb"

echo "Installing Kong"
dpkg -i /tmp/kong.deb

