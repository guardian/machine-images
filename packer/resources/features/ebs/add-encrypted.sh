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

    -x            indicates that the created volume should be deleted on
                  termination

    -k key-arn    [optional] Specify a customer master key to use when encrypting.

    -t type       [optional] Specify a volume type.

    -i iops       [when type=io1] Specify the number of provisioned IOPS

    -o options    [optional] Specify file system options (defaults to "defaults")

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

DELETE_ON_TERMINATION="false"
OPTIONS="defaults"

# Process options
while getopts d:m:u:s:k:t:i:xo:h FLAG; do
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
    i)
      IOPS=$OPTARG
      ;;
    x)
      DELETE_ON_TERMINATION="true"
      ;;
    o)
      OPTIONS=$OPTARG
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
  if [ "${VOLUME_TYPE}" == "io1" ]; then
    if [ -z "${IOPS}" ]; then
      echo "Must specify -i when type is io1"
      exit 1
    fi
    OPTIONAL_ARGS="${OPTIONAL_ARGS} --iops ${IOPS}"
  fi
fi

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
source ${SCRIPTPATH}/../templating/metadata.sh
eval declare -A SUBS=$(get_metadata -t)

function sub {
  echo ${SUBS[${1}]}
}
STACK=$(sub "tag.Stack")
STAGE=$(sub "tag.Stage")
APP=$(sub "tag.App")

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

function wait_for_device {
  local DEVICE=$1
  local counter=0
  while [ ${counter} -lt 60 -a ! -b "${DEVICE}" ]; do
    counter=$((counter + 1))
    sleep 1
  done
  if [ ! -b "${DEVICE}" ]; then
    echo "Device ${DEVICE} still not available after 60 seconds"
    return 1
  fi
}

function copy_tags_from_instance {
  local TAGS="Key=instance,Value=${INSTANCE}"
  for key in "${!SUBS[@]}"; do
    if [[ ${key} == tag.* ]]; then
      tagName=${key#tag.}
      if [[ ${tagName} != aws:* ]]; then
        TAGS="${TAGS} Key=${tagName},Value=${SUBS[$key]}"
      fi
    fi
  done

  local ret=0
  local CMD="aws ec2 create-tags --region ${REGION} --resources $@ --tags ${TAGS}"
  >&2 echo "Copying tags: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error copying tags: ${RESULT}"
    return 1
  fi
}

function set_delete_on_termination {
  local VOLUME=$1
  local ret=0
  local MAPPING="[{\"DeviceName\":\"/dev/sd${DEVICE_LETTER}\",\"Ebs\":{\"DeleteOnTermination\":${DELETE_ON_TERMINATION}}}]"
  local CMD="aws ec2 modify-instance-attribute --region ${REGION} --instance-id ${INSTANCE} --block-device-mappings ${MAPPING}"
  >&2 echo "Setting delete on termination flag: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error setting flag: ${RESULT}"
    return 1
  fi
}

VOLUME_ID=$(create_volume)
ec2_wait volume-available ${VOLUME_ID}
attach_volume ${VOLUME_ID}
ec2_wait volume-in-use ${VOLUME_ID}
# Sleep to wait for the OS to process the new device
UBUNTU_DEVICE="/dev/xvd${DEVICE_LETTER}"
wait_for_device ${UBUNTU_DEVICE}
if [ -n "${MOUNTPOINT}" ]; then
  mkdir -p ${MOUNTPOINT}
  mkfs -t ext4 ${UBUNTU_DEVICE}
  echo "${UBUNTU_DEVICE} ${MOUNTPOINT} ext4 ${OPTIONS} 0 0" >> /etc/fstab
  mount ${MOUNTPOINT}
  if [ -n "${MOUNT_USER}" ]; then
    chown ${MOUNT_USER} ${MOUNTPOINT}
  fi
fi
copy_tags_from_instance ${VOLUME_ID}
set_delete_on_termination ${VOLUME_ID}
