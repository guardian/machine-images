#!/bin/bash
# This script must be run as root
set -e

# Make sure dnsmasq is installed
if ! (dpkg -s dnsmasq 2> /dev/null > /dev/null); then
    apt-get install -y dnsmasq
fi
