#!/usr/bin/env bash
set -e

function HELP {
>&2 cat << EOF

  Usage: ${0} [-p package | -b bucket]

  This script deploys a sbt-native-packager tar.gz file.

    -b bucket     The S3 bucket to download the artifact from.
                  Note that the URL will be generated automatically from the
                  stack, stage and app tags.

    -t extension  The file extension/type of the package to deploy
                  (default=tar.gz). Currently knows how to deploy gzipped tar
                  files.

    -o s3-loc     The origin location of a properties file in S3

    -d file       The destination location of the properties file on local disk

    -u user       The user to create and deploy as, defaults to the 'Stack' tag.

    -a app        The name of the native-package app. This defaults to the
                  'App' tag but can be overriden here. It should match the app
                  name in the SBT build config.

    -s            Start the application after deployment

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

DEFAULT_TYPE="tar.gz"
TYPE=${DEFAULT_TYPE}
# this is often set by the shell, make sure it is clear
unset USER

# Process options
while getopts b:t:u:a:o:d:sh FLAG; do
  case $FLAG in
    b)
      BUCKET=$OPTARG
      ;;
    t)
      TYPE=$OPTARG
      ;;
    u)
      USER=$OPTARG
      ;;
    a)
      TARBALL_APP=$OPTARG
      ;;
    o)
      ORIGIN=$OPTARG
      ;;
    d)
      DESTINATION=$OPTARG
      ;;
    s)
      START="true"
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

if [ -z "${USER}" ]; then
  USER=${STACK}
fi
HOME_DIR="/home/${USER}"

if [ -z "${TARBALL_APP}" ]; then
  TARBALL_APP=${APP}
fi

# Make user
if ! getent passwd ${USER} >/dev/null; then
  /usr/sbin/useradd -m -r --shell /sbin/nologin -d ${HOME_DIR} ${USER}
fi

# create the logs dir used in the upstart script
mkdir -p ${HOME_DIR}/logs
chown ${USER} ${HOME_DIR}/logs

S3LOCATION="s3://${BUCKET}/${STACK}/${STAGE}/${APP}/${APP}.${TYPE}"

# install the update script
UPDATE_SCRIPT="${SCRIPTPATH}/update.sh"
/opt/features/templating/subst.sh S3LOCATION=${S3LOCATION} HOME_DIR=${HOME_DIR} TYPE=${TYPE} \
                ORIGIN=${ORIGIN} DESTINATION=${DESTINATION} \
                ${SCRIPTPATH}/update.sh.template > ${UPDATE_SCRIPT}
chmod a+x ${UPDATE_SCRIPT}

# install systemd file
/opt/features/templating/subst.sh USER=${USER} APP=${TARBALL_APP} UPDATE_SCRIPT=${UPDATE_SCRIPT} \
                ${SCRIPTPATH}/systemd.service.template > /etc/systemd/system/${APP}.service

# optionally start
if [ "${START}" == "true" ]; then
  systemctl start ${APP}
fi
