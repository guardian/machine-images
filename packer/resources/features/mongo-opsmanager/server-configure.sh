#!/bin/bash
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# install the upstart and configuration files for application and blockstore
${SCRIPTPATH}/scripts/server_configure.rb --templateDir ${SCRIPTPATH}/templates

# start the mongo databases
service mongod-application start
service mongod-blockstore start