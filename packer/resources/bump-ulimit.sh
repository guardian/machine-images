#!/bin/bash
# this is run as root

echo "# Added by machine-images (bump-ulimit.sh in github.com/guardian/machine-images)" >> /etc/security/limits.conf
echo "*  soft  nofile  16384" >> /etc/security/limits.conf
echo "*  hard  nofile  16384" >> /etc/security/limits.conf
