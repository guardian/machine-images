#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Run set-readahead for new volumes since boot
service set-readahead start

OM_URL=$( ${SCRIPTPATH}/scripts/opsmanager_url.rb )

# Download and install automation agent
PACKAGE=mongodb-mms-automation-agent-manager_latest_amd64.deb
pushd /tmp
curl -OL ${OM_URL}/download/agent/automation/${PACKAGE}
dpkg -i ${PACKAGE}
popd

CONFIG_FILE="/etc/mongodb-mms/automation-agent.config"
${SCRIPTPATH}/scripts/agent_configure.rb -c ${CONFIG_FILE} -t ${SCRIPTPATH}/templates/automation-agent.config.erb

# Start agent
start mongodb-mms-automation-agent

# create mongodb logging location
mkdir -p /var/log/mongodb
chown mongodb:mongodb /var/log/mongodb

# chown the data mount
chown mongodb /var/lib/mongodb

# Run the replica set initialisation script
${SCRIPTPATH}/scripts/opsmanager_add_self_to_replset.rb
