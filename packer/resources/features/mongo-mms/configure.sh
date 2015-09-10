#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

MMS_URL=$( ${SCRIPTPATH}/scripts/mms_url.rb )

# Download and install automation agent
pushd /tmp
curl -OL ${MMS_URL}/download/agent/automation/mongodb-mms-automation-agent-manager_2.0.12.1296-1_amd64.deb
dpkg -i mongodb-mms-automation-agent-manager_2.0.12.1296-1_amd64.deb
popd

CONFIG_FILE="/etc/mongodb-mms/automation-agent.config"
${SCRIPTPATH}/scripts/agent_configure.rb -c ${CONFIG_FILE} -t ${SCRIPTPATH}/automation-agent.config.erb

# Start agent
start mongodb-mms-automation-agent

# Run the replica set initialisation script
#${SCRIPTPATH}/scripts/mongodb_add_self_to_replset.rb
