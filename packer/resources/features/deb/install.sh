#!/usr/bin/env bash
set -e

function HELP {
>&2 cat << EOF

  Usage: ${0} -b bucket

  This script deploys an application built as a deb

    -b bucket     The S3 bucket to download the artifact from.
                  Note that the URL will be generated automatically from the
                  stack, stage and app tags.

    -a app        The name of the app, which is assumed to correspond to the name of 
									deb file. This defaults to the
                  'App' tag but can be overriden here. It should match the app
                  name in the SBT build config.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# this is often set by the shell, make sure it is clear
unset USER

# Process options
while getopts b:t:u:a:sh FLAG; do
  case $FLAG in
    b)
      BUCKET=$OPTARG
      ;;
    a)
      APP_NAME=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${BUCKET}" ]; then
  echo "Must specify an S3 bucket"
  exit 1
fi

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
source ${SCRIPTPATH}/../templating/metadata.sh
eval declare -A SUBS=$(get_metadata -t)

function sub {
  echo ${SUBS[${1}]}
}
REGION=$(get_region)
STACK=$(sub "tag.Stack")
STAGE=$(sub "tag.Stage")
APP=$(sub "tag.App")

if [ -z "${APP_NAME}" ]; then
  APP_NAME=${APP}
fi

# Install an application that was packaged by the sbt-native-packager
# download
LOCAL_DEB=$(mktemp --suffix=".${TYPE}" /tmp/app-deb.XXXXXX)
aws s3 cp "s3://${BUCKET}/${STACK}/${STAGE}/${APP}/${APP}_1.0_all.deb" \
					"${LOCAL_DEB}" --region ${REGION}

dpkg -i $LOCAL_DEB
