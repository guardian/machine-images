#!/bin/bash
#
# Downloads and extracts the Logstash tarball
#
# This script must be run as root
set -e

LOGSTASH_VERSION=1.4.2
FEATURE_ROOT=/opt/features/logstash

if wget -qO $FEATURE_ROOT/logstash.tar.gz https://download.elastic.co/logstash/logstash/logstash-${LOGSTASH_VERSION}.tar.gz
then
    tar xf $FEATURE_ROOT/logstash.tar.gz -C $FEATURE_ROOT
    mv $FEATURE_ROOT/logstash-* $FEATURE_ROOT/logstash
else
    echo 'Failed to download Logstash'
    exit 1
fi
