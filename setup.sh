#!/bin/bash
# Install packer locally
set -e

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
PACKER_DIR="${SCRIPTPATH}/packer_bin"

PLATFORM=$(uname)
PACKER_VERSION="0.8.1"

if [ -x "${PACKER_DIR}/packer" ]; then
  if ${PACKER_DIR}/packer version | grep -q "${PACKER_VERSION}"
  then
    echo "Packer ${PACKER_VERSION} already installed"
    exit 0
  else
    echo "Packer installed, but not version ${PACKER_VERSION} - delete packer_bin directory and run again to install if desired"
    exit 1
  fi
fi

case "$PLATFORM" in
  Darwin)
    PACKER_URI="https://dl.bintray.com/mitchellh/packer/packer_${PACKER_VERSION}_darwin_amd64.zip"
    ;;
  Linux)
    PACKER_URI="https://dl.bintray.com/mitchellh/packer/packer_${PACKER_VERSION}_linux_amd64.zip"
    ;;
  *)
    echo "Unknown OS, please install packer yourself"
    exit 2
    ;;
esac

PACKER_FILE=$(mktemp /tmp/packer-XXXXXX)
if [ $? -ne 0 ]; then
  echo "$0: can't create temp file for packer installation"
  exit 3
fi

trap "{ rm ${PACKER_FILE}; }" EXIT

curl -Lo ${PACKER_FILE} "${PACKER_URI}"
if [ $? -ne 0 ]; then
  echo "$0: failed to download packer"
  exit 4
fi

mkdir -p $PACKER_DIR
$( cd ${PACKER_DIR}; unzip -q $PACKER_FILE )
