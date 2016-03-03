#!/bin/bash
#
# Downloads Nginx
#
# This script must be run as root
set -e
# Download package and its dependencies
apt-get install --yes --download-only nginx
