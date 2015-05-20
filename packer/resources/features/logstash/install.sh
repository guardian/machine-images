#!/bin/bash
#
# * Symlinks Logstash to /opt/logstash
# * Creates an init script for Logstash
#
# This script must be run as root
set -e

USAGE="Usage: $0 username config-file

Example: $0 content-api /home/content-api/logstash-shipper.conf
"
USER=${1?"Username missing. $USAGE"}
CONFIGFILE=${2?"Config file path missing. $USAGE"}

ln -s /opt/features/logstash/logstash /opt/logstash

# TODO could use the handy substitution script once #23 is merged
sed \
  -e 's/@USER@/$USER/g' \
  -e 's/@CONFIGFILE@/$CONFIGFILE/g' \
  /opt/features/logstash/logstash.conf.template > /etc/init/logstash.conf

echo "Logstash is now installed as an Upstart service. You can start it by running 'sudo start logstash'."
