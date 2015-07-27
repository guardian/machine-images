#!/bin/bash

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )

# See http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/enhanced-networking.html
pushd ${SCRIPTPATH}
tar -xzf ixgbevf-2.16.1.tar.gz
pushd ${SCRIPTPATH}/ixgbevf-2.16.1/src
cp ${SCRIPTPATH}/patch.kcompat.h .
patch <patch.kcompat.h
make install
modprobe ixgbevf
update-initramfs -c -k all
popd
rm -r ixgbevf-2.16.1/
popd
