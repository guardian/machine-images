#!/bin/bash
#
# Configuration script for the Kong feature.
#
# Given a list of Cassandra hostnames, rewrites kong.yml to use those hosts (on port 9042)
#
# This script must be run as root
set -e

USAGE="Usage: $0 [cassandrahost1 [cassandrahost2 ...]]

Example: $0 1.2.3.4 5.6.7.8
"

if (( $# > 0 )); then
  search='        - "localhost:9042"'
  replacement=''
  for host in "$@"; do
    replacement="$replacement        - \"${host}:9042\"\n"
  done

  echo "Backing up kong.yml to /etc/kong/kong.yml.bak"
  cp /etc/kong/kong.yml{,.bak}

  echo "Writing Cassandra hostnames to kong.yml"
  # Use perl because sed doesn't play well with newlines
  perl -pe "s/${search}/${replacement}/" /etc/kong/kong.yml.bak > /etc/kong/kong.yml
else
  echo "Not doing anything because you didn't give me any Cassandra hosts."
fi
