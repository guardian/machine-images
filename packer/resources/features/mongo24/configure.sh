#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Install the config file to /etc/mongodb.conf
CONFIG_FILE=/etc/mongodb.conf
cp ${CONFIG_FILE} ${CONFIG_FILE}.original
touch ${CONFIG_FILE}
chmod 444 ${CONFIG_FILE}

# Install the replica set key file
KEY_FILE=/var/lib/mongodb/keyFile
touch ${KEY_FILE}
chown mongodb:mongodb ${KEY_FILE}
chmod 400 ${KEY_FILE}

${SCRIPTPATH}/scripts/mongodb_configure.rb -k ${KEY_FILE} -c ${CONFIG_FILE} -t ${SCRIPTPATH}/mongodb.conf.erb

# Restart mongodb
systemctl restart mongodb

# Run the replica set initialisation script
${SCRIPTPATH}/scripts/mongodb_add_self_to_replset.rb
