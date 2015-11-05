#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Run set-readahead for new volumes since boot
service set-readahead start

OM_URL=$( ${SCRIPTPATH}/scripts/opsmanager_url.rb -a db)

# Download and install automation agent
PACKAGE=mongodb-mms-automation-agent-manager_2.0.12.1296-1_amd64.deb
pushd /tmp
curl -OL ${OM_URL}/download/agent/automation/${PACKAGE}
dpkg -i ${PACKAGE}
popd

CONFIG_FILE="/etc/mongodb-mms/automation-agent.config"
${SCRIPTPATH}/scripts/agent_configure.rb -c ${CONFIG_FILE} -t ${SCRIPTPATH}/templates/automation-agent.config.erb -a db

# Start agent
start mongodb-mms-automation-agent

# Install backup agent
${SCRIPTPATH}/scripts/opsmanager_install_backup_agent.rb -a db

# Make backup user
if ! getent passwd backup >/dev/null; then
  /usr/sbin/useradd -M -r --shell /sbin/nologin backup
fi
chown backup /backup
touch /tmp/last_snapshot_downloaded.txt
