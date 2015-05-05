#!/bin/bash
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# try to get build branch
if [ -n "${TEAMCITY_BUILD_PROPERTIES_FILE}" ]; then
  CONFIG_FILE=$( grep "teamcity.configuration.properties.file=" ${TEAMCITY_BUILD_PROPERTIES_FILE} | cut -d'=' -f2 )
  export BUILD_BRANCH=$( grep "teamcity.build.branch=" ${CONFIG_FILE} | cut -d'=' -f2 )
  export BUILD_VCS_REF=$( grep "build.vcs.number=" ${CONFIG_FILE} | cut -d'=' -f2 )
fi

# install packer if needed
bash ${SCRIPTPATH}/setup.sh

# now run packer
(
  cd "${SCRIPTPATH}/packer"
  bash build.sh
)
