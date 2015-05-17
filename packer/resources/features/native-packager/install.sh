#!/usr/bin/env bash
set -e
set -x

function HELP {
>&2 cat << EOF

  Usage: ${0} [-p package | -b bucket]

  This script deploys a sbt-native-packager tar.gz file.

    -p package    The tar.gz package file to deploy

    -b bucket     The S3 bucket to download the artifact from.
                  Note that the URL will be generated automatically from the
                  stack, stage and app tags.

    -u user       The user to create and deploy as

    -s            Start the application after deployment

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

DEFAULT_USER="ubuntu"
USER=${DEFAULT_USER}

# Process options
while getopts b:p:u:sh FLAG; do
  case $FLAG in
    b)
      BUCKET=$OPTARG
      ;;
    p)
      PACKAGE=$OPTARG
      ;;
    u)
      USER=$OPTARG
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

if [ -z "${PACKAGE}" -a -z "${BUCKET}" ]; then
  echo "Must specify a package or S3 bucket"
  exit 1
fi

HOME_DIR="/home/${USER}"

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
source ${SCRIPTPATH}/../templating/subs.sh
eval declare -A SUBS=$(get_substitution_map -t)

function sub {
  echo ${SUBS[${1}]}
}

Make user
if [ "${USER}" != "${DEFAULT_USER}" ]; then
  /usr/sbin/useradd -M -r --shell /sbin/nologin -d ${HOME_DIR} ${USER}
fi

# create the logs dir used in the upstart script
mkdir -p ${HOME_DIR}/logs
chown ${USER} ${HOME_DIR}/logs

# Install an application that was packaged by the sbt-native-packager
# download
# TODO: Use tmp file
STACK=$(sub "tag.Stack")
STAGE=$(sub "tag.Stage")
APP=$(sub "tag.App")
if [ -n "${BUCKET}" ]; then
  aws s3 cp "s3://${BUCKET}/${STACK}/${STAGE}/${APP}/${APP}.tgz" \
            "/tmp/${APP}.tag.gz"
fi

# get name
FILENAME=${PACKAGE%/}
APP=${FILENAME##\.tgz}

# unpack
tar -C ${HOME_DIR} -xzf ${PACKAGE}
chown -R ${USER} ${HOME_DIR}/${APP}

# install upstart/systemd file
/opt/feature/templating/subst.sh USER=${USER} APP=${APP} \
                                 upstart.conf.template > /etc/init/${APP}.conf

# optionally start
if [ "${START}" == "true" ]; then
  start ${APP}
fi
