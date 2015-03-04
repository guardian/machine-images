#!/bin/bash -x
set -e
# try to get build branch
if [ -n "${TEAMCITY_BUILD_PROPERTIES_FILE}" ]; then
  CONFIG_FILE=$( grep "teamcity.configuration.properties.file=" ${TEAMCITY_BUILD_PROPERTIES_FILE} | cut -d'=' -f2 )
  export BUILD_BRANCH=$( grep "teamcity.build.branch=" ${CONFIG_FILE} | cut -d'=' -f2 )
  export BUILD_VCS_REF=$( grep "build.vcs.number=" ${CONFIG_FILE} | cut -d'=' -f2 )
fi

pushd packer
bash build.sh
popd
