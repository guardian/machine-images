#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Run set-readahead for new volumes since boot
service set-readahead start

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
service mongodb restart

# Run the replica set initialisation script
${SCRIPTPATH}/scripts/mongodb_add_self_to_replset.rb "$@"

# Download and install the automation agent
OM_URL=$( ${SCRIPTPATH}/../mongo-opsmanager/scripts/opsmanager_url.rb )

# Download and install automation agent
PACKAGE=mongodb-mms-automation-agent-manager_2.0.12.1296-1_amd64.deb
pushd /tmp
curl -OL ${OM_URL}/download/agent/automation/${PACKAGE}
dpkg -i ${PACKAGE}
popd

CONFIG_FILE="/etc/mongodb-mms/automation-agent.config"
${SCRIPTPATH}/../mongo-opsmanager/scripts/agent_configure.rb -c ${CONFIG_FILE} -t ${SCRIPTPATH}/../mongo-opsmanager/templates/automation-agent.config.erb

# Start agent
start mongodb-mms-automation-agent