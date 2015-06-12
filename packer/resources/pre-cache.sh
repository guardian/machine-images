#!/bin/bash
# this is run as root

function new_section {
  echo
  echo $(date +"%F %T") $1
  echo "----------------------------------------------------------------------------------------"
}

set -e

## Pre-cache features
new_section "Pre-caching features"
for feature in /opt/features/*; do
  if [ -e "$feature/pre-cache.sh" ]; then
    echo "Pre-caching $(basename $feature) feature"
    bash "$feature/pre-cache.sh"
  fi
done
