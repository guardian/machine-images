#!/usr/bin/env bash
function ensure_ssh_directory_exists {
  local TARGET_USER=$1
  eval TARGET_USER_HOME="~${TARGET_USER}"
  local TARGET_USER_GROUP=`id -gn ${TARGET_USER}`
  local TARGET_DIRECTORY="${TARGET_USER_HOME}/.ssh/"
  local ret=0
  local CMD="mkdir -p ${TARGET_DIRECTORY}"
  >&2 echo "Ensuring ${TARGET_DIRECTORY} exists: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error ensuring ${TARGET_DIRECTORY} exists"
    return 1
  fi
  local CMD="chown -R ${TARGET_USER}:${TARGET_USER_GROUP} ${TARGET_DIRECTORY}"
  >&2 echo "Ensuring ownership for ${TARGET_DIRECTORY}: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error ensuring ownership for ${TARGET_DIRECTORY}"
    return 1
  fi
  local CMD="chmod -R 700 ${TARGET_DIRECTORY}"
  >&2 echo "Ensuring permissions for ${TARGET_DIRECTORY}: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error ensuring permissions for ${TARGET_DIRECTORY}"
    return 1
  fi
}

function check_ssh_key_url_is_valid {
  local S3_URL=$1
  local ret=0
  local CMD="aws s3 ls ${S3_URL}"
  >&2 echo "Checking whether SSH key file exists in S3: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "No such file in S3: ${S3_URL}"
    return 1
  fi
}

function fetch_ssh_key_from_url {
  local S3_URL=$1
  local LOCAL_FILE=$2
  local ret=0
  local CMD="aws s3 cp ${S3_URL} ${LOCAL_FILE}"
  >&2 echo "Downloading SSH key file to local temporary file: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error downloading SSH key file: ${RESULT}"
    return 1
  fi
}

function install_ssh_key_for_user {
  local TARGET_USER=$1
  local TEMPORARY_KEY_FILE=$2
  eval TARGET_USER_HOME="~${TARGET_USER}"
  local TARGET_KEY_FILE="${TARGET_USER_HOME}/.ssh/authorized_keys"
  local ret=0
  local CMD="mv ${TEMPORARY_KEY_FILE} ${TARGET_KEY_FILE}"
  >&2 echo "Overwriting user's authorized_keys file with downloaded file: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error overwriting authorized_keys. Has the downloaded file already been moved?"
    return 1
  fi
}

function ensure_key_file_permissions {
  local TARGET_USER=$1
  local TEMPORARY_KEY_FILE=$2
  eval TARGET_USER_HOME="~${TARGET_USER}"
  local TARGET_USER_GROUP=`id -gn ${TARGET_USER}`
  local TARGET_KEY_FILE="${TARGET_USER_HOME}/.ssh/authorized_keys"
  local ret=0
  local CMD="chmod 600 ${TARGET_KEY_FILE}"
  >&2 echo "Ensuring file permissions for key file: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error ensuring file permissions for key file"
    return 1
  fi
  local CMD="chown ${TARGET_USER}:${TARGET_USER_GROUP} ${TARGET_KEY_FILE}"
  >&2 echo "Ensuring file ownership for key file: ${CMD}"
  RESULT=`${CMD}` || ret=$?
  if [ ${ret} != 0 ]; then
    >&2 echo "Error ensuring file ownership for key file"
    return 1
  fi
}