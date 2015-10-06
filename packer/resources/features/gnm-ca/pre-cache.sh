#!/bin/bash
# This script must be run as root
set -e

# Make sure ca-certificates-java is installed
if ! (dpkg -s ca-certificates-java 2> /dev/null > /dev/null); then
    apt-get install -y ca-certificates-java
fi
