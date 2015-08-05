#!/bin/bash
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
touch /etc/mongod.conf
chmod 444 /etc/mongod.conf
erb -T - ${SCRIPTPATH}/mongod.conf.erb > /etc/mongod.conf

# Install the replica set key file
${SCRIPTPATH}/scripts/mongodb_install_keyfile.rb

# Restart mongodb
systemctl restart mongodb

# Run the replica set initialisation script
# ${SCRIPTPATH}/scripts/mongod_add_self_to_replset.rb
