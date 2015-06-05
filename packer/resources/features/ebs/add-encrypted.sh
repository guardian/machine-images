#!/usr/bin/env bash
set -e

function HELP {
>&2 cat << EOF

  Usage: ${0} -d device-letter -m mountpoint -s size [-k key-arn] [-u user] [-t type]

  This script creates and attaches an encrypted EBS volume. This is wrapper
  around the AWS EC2 CLI and you should see the following docs for clarification
  to expected parameters:
    http://docs.aws.amazon.com/cli/latest/reference/ec2/create-volume.html
    http://docs.aws.amazon.com/cli/latest/reference/ec2/attach-volume.html

    -d dev-letter The device letter. This should be a single character (usually
                  h or later) that is used to identify the device. Note that the
                  device name specified by Amazon and understood by Ubuntu are
                  different.
                  (e.g. Specifying h will appear as /dev/sdh in Amazon and map
                  to /dev/xvdh under Ubuntu).

    -m mountpoint The fs mountpoint (will be created if necessary).

    -u user       [optional] chown the mountpoint to this user.

    -s size       The device size.

    -k key-arn    [optional] Specify a customer master key to use when encrypting.

    -t type       [optional] Specify a volume type.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts d:m:u:s:k:t:h FLAG; do
  case $FLAG in
    d)
      DEVICE_LETTER=$OPTARG
      ;;
    m)
      MOUNTPOINT=$OPTARG
      ;;
    u)
      MOUNT_USER=$OPTARG
      ;;
    s)
      SIZE=$OPTARG
      ;;
    k)
      CMK=$OPTARG
      ;;
    t)
      VOLUME_TYPE=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${DEVICE_LETTER}" ]; then
  echo "Must specify a device letter"
  exit 1
fi

if [ -z "${SIZE}" ]; then
  echo "Must specify a volume size"
  exit 1
fi

OPTIONAL_ARGS=""

if [ -n "${CMK}" ]; then
  OPTIONAL_ARGS="${OPTIONAL_ARGS} --kms-key-id ${CMK}"
fi

if [ -n "${VOLUME_TYPE}" ]; then
  OPTIONAL_ARGS="${OPTIONAL_ARGS} --volume-type ${VOLUME_TYPE}"
fi

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
source ${SCRIPTPATH}/../templating/metadata.sh

INSTANCE=$(ec2metadata --instance-id)
REGION=$(get_region)
ZONE=$(ec2metadata --availability-zone)

function create_volume {
  local ret=0
  local CMD="aws ec2 create-volume --region ${REGION} --availability-zone ${ZONE} --size ${SIZE} --encrypted ${OPTIONAL_ARGS}"
  >&2 echo "Creating volume: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} == 0 ]; then
    (echo "${RESULT}" | jq -r '.VolumeId')
  else
    >&2 echo "Error creating volume: ${RESULT}"
    return 1
  fi
}

function ec2_wait {
  local COMMAND=$1
  local VOLUME_ID=$2
  # We sleep for five seconds here to make this quicker in the typical case, the
  # wait command polls every 15s, but actions are normally a lot quicker
  >&2 echo "Sleeping for 5 seconds to wait for async action to happen"
  sleep 5

  local ret=0
  local CMD="aws ec2 wait ${COMMAND} --region ${REGION} --volume-ids ${VOLUME_ID}"
  >&2 echo "Waiting for state ${COMMAND}: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error attaching volume: ${RESULT}"
    return 1
  fi
}

function attach_volume {
  local VOLUME_ID=$1
  local ret=0
  local CMD="aws ec2 attach-volume --region ${REGION} --volume-id ${VOLUME_ID} --instance-id ${INSTANCE} --device /dev/sd${DEVICE_LETTER}"
  >&2 echo "Attaching volume: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error attaching volume: ${RESULT}"
    return 1
  fi
}

VOLUME_ID=$(create_volume)
ec2_wait volume-available ${VOLUME_ID}
attach_volume ${VOLUME_ID}
ec2_wait volume-in-use ${VOLUME_ID}
if [ -n "${MOUNTPOINT}" ]; then
  mkdir -p ${MOUNTPOINT}
  mkfs -t ext4 /dev/xvd${DEVICE_LETTER}
  mount /dev/xvd${DEVICE_LETTER} ${MOUNTPOINT}
  if [ -n "${MOUNT_USER}" ]; then
    chown ${MOUNT_USER} ${MOUNTPOINT}
  fi
fi
