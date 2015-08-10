#!/bin/bash
set -e

# Script to configure a mongo node
SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# Get the tags for this instance
source ${SCRIPTPATH}/../templating/metadata.sh
eval declare -A SUBS=$(get_metadata -t)

function sub {
  echo ${SUBS[${1}]}
}

export STACK=$(sub "tag.Stack")
export STAGE=$(sub "tag.Stage")
export APP=$(sub "tag.App")

# Install the config file to /etc/mongodb.conf
CONFIG_FILE=/etc/mongodb.conf
cp ${CONFIG_FILE} ${CONFIG_FILE}.original
touch ${CONFIG_FILE}
chmod 444 ${CONFIG_FILE}
erb -T - ${SCRIPTPATH}/mongodb.conf.erb > ${CONFIG_FILE}

# Install the replica set key file
KEY_FILE=/var/lib/mongodb/keyFile
touch ${KEY_FILE}
chown mongodb:mongodb ${KEY_FILE}
chmod u+r,og-rwx ${KEY_FILE}
${SCRIPTPATH}/scripts/mongodb_fetch_keyfile.rb > ${KEY_FILE}


# Restart mongodb
systemctl restart mongodb

# Run the replica set initialisation script
${SCRIPTPATH}/scripts/mongod_add_self_to_replset.rb
