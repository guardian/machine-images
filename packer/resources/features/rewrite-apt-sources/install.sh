#!/bin/bash
#
# Rewrite all EC2-specific apt sources to point to the canonical servers.
# This is useful as a temporary workaround when the Ubuntu EC2 mirrors break, which happens occasionally.
#
# This script must be run as root
set -e

echo Rewriting apt sources files to remove references to EC2 mirrors of Ubuntu repos...

shopt -s nullglob
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*
do
  echo Rewriting $f
  sed -i".bak" -r -e 's/(http(s?)):\/\/[a-z0-9-]+\.ec2\.archive\.ubuntu.com/\1:\/\/archive.ubuntu.com/g'
  echo Done. Backup saved at ${f}.bak
done

echo
echo Finished. You will need to run apt update before the changes take effect.
