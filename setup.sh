#!/bin/bash
# Install packer locally

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

PLATFORM=$(uname)
PACKER_VERSION="0.7.5"

case "$PLATFORM" in
  Darwin)
    PACKER_URI="https://dl.bintray.com/mitchellh/packer/packer_${PACKER_VERSION}_darwin_amd64.zip"
    ;;
  Linux)
    PACKER_URI="https://dl.bintray.com/mitchellh/packer/packer_${PACKER_VERSION}_linux_amd64.zip"
    ;;
  *)
    echo "Unknown OS, please install packer yourself"
    exit 1
    ;;
esac

PACKER_FILE=$(mktemp /tmp/packer-XXXXXX)
if [ $? -ne 0 ]; then
  echo "$0: can't create temp file for packer installation"
  exit 2
fi

trap "{ rm ${PACKER_FILE}; }" EXIT

curl -Lo ${PACKER_FILE} "${PACKER_URI}"
if [ $? -ne 0 ]; then
  echo "$0: failed to download packer"
  exit 3
fi

PACKER_DIR="${SCRIPTPATH}/packer_bin"

mkdir -p $PACKER_DIR
$( cd ${PACKER_DIR}; unzip -q $PACKER_FILE )
