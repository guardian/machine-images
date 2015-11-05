#!/bin/bash
#
# Downloads Node.JS
#
# This script must be run as root
set -e
set -o pipefail

NODEJS_VERSION=4.x

# Creates apt sources list file
curl -sL https://deb.nodesource.com/setup_${NODEJS_VERSION} | bash -
# Download package and its dependencies
apt-get install --yes --download-only nodejs
