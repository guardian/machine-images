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
while getopts b:t:u:a:sh FLAG; do
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
  /usr/sbin/useradd -M -r --shell /sbin/nologin -d ${HOME_DIR} ${USER}
fi

# create the logs dir used in the upstart script
mkdir -p ${HOME_DIR}/logs
chown ${USER} ${HOME_DIR}/logs

# Install an application that was packaged by the sbt-native-packager
# download
PACKAGE_FILE=$(mktemp --suffix=".${TYPE}" /tmp/native-package.XXXXXX)
BUCKET_PREFIX="s3://${BUCKET}/${STACK}/${STAGE}/${APP}"
aws s3 cp "${BUCKET_PREFIX}/${APP}.${TYPE}" \
          "${PACKAGE_FILE}" --region ${REGION}

# unpack
case "${TYPE}" in
    'tar.gz'|'tgz')
      tar -C ${HOME_DIR} -xzf ${PACKAGE_FILE}
      ;;
    'zip')
      unzip ${PACKAGE_FILE} -d ${HOME_DIR}
      ;;
    *)
      echo "Unknown type: '${TYPE}'"
      exit 1
      ;;
esac

chown -R ${USER} ${HOME_DIR}/${TARBALL_DIR}

INIT=$(cat /proc/1/comm)

case "${INIT}" in
  init)
    # install upstart file
    aws s3 cp "${BUCKET_PREFIX}/${APP}.conf" "/etc/init/${APP}.conf" --region ${REGION} || {
      /opt/features/templating/subst.sh USER=${USER} APP=${TARBALL_APP} \
                    ${SCRIPTPATH}/upstart.conf.template > /etc/init/${APP}.conf
    }

    # optionally start
    if [ "${START}" == "true" ]; then
      start ${APP}
    fi
    ;;
  systemd)
    # install systemd file
    aws s3 cp "${BUCKET_PREFIX}/${APP}.service" "/etc/systemd/system/${APP}.service" --region ${REGION} || {
      /opt/features/templating/subst.sh USER=${USER} APP=${TARBALL_APP} \
                    ${SCRIPTPATH}/systemd.service.template > /etc/systemd/system/${APP}.service
    }
    # optionally start
    if [ "${START}" == "true" ]; then
      systemctl start ${APP}
    fi
    ;;
esac