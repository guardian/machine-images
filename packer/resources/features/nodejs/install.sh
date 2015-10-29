#!/bin/bash
#
# Install Node.JS
#
# This script must be run as root
set -e

# The packages should already be downloaded by pre-cache
apt-get install --yes nodejs
