#!/bin/bash
#
# Install ELK stack
#
# This script must be run as root
set -e

FEATURE_ROOT=/opt/features/elk-stack
KIBANA_VERSION=4.0.2

## Add repositories we are going to use
wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb http://packages.elastic.co/elasticsearch/1.4/debian stable main" > /etc/apt/sources.list.d/elasticsearch.list
echo "deb http://packages.elastic.co/logstash/1.5/debian stable main" > /etc/apt/sources.list.d/logstash.list
add-apt-repository -y ppa:chris-lea/node.js
sleep 1

## Update index and install packages
apt-get update
apt-get --yes --force-yes install ruby ruby-dev logstash elasticsearch=1.4.4 \
    nodejs python-pip golang

## Install Elasticsearch plugins
/usr/share/elasticsearch/bin/plugin --install elasticsearch/elasticsearch-cloud-aws/2.4.2
/usr/share/elasticsearch/bin/plugin --install mobz/elasticsearch-head
/usr/share/elasticsearch/bin/plugin --install lukas-vlcek/bigdesk
/usr/share/elasticsearch/bin/plugin --install karmi/elasticsearch-paramedic
/usr/share/elasticsearch/bin/plugin --install royrusso/elasticsearch-HQ

## Install the curator
pip install elasticsearch-curator

# Add script and install crontab
mkdir -p /opt/bin
cp $FEATURE_ROOT/housekeeping.sh /opt/bin
crontab -u elasticsearch - << EOM
0 1 * * * /bin/bash /opt/bin/housekeeping.sh
EOM

## Install the template config files (need to be configured in cloud-init at instance boot)
cp $FEATURE_ROOT/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.template

## Install logstash config
cp $FEATURE_ROOT/logstash-indexer.conf /etc/logstash/conf.d/logstash-indexer.conf

## Install logstash plugins
su - logstash -s /bin/sh -c '/opt/logstash/bin/plugin install logstash-input-kinesis'

## Install Kibana
wget https://download.elastic.co/kibana/kibana/kibana-${KIBANA_VERSION}-linux-x64.tar.gz -O /tmp/kibana-${KIBANA_VERSION}-linux-x64.tar.gz
tar xf /tmp/kibana-${KIBANA_VERSION}-linux-x64.tar.gz -C /opt
mv /opt/kibana-${KIBANA_VERSION}-linux-x64 /opt/kibana
 
useradd -M -r -U -s /bin/false -d /opt/kibana kibana
mkdir /var/log/kibana
chown kibana:kibana /var/log/kibana

# Install Google Auth Proxy
mkdir /opt/oauth2_proxy
useradd -M -r -U -s /bin/false -d /opt/oauth2_proxy oauth2-proxy
cd /tmp
wget https://github.com/bitly/oauth2_proxy/releases/download/v1.1.1/google_auth_proxy-1.1.1.linux-amd64.go1.4.2.tar.gz
tar -zxf google_auth_proxy-1.1.1.linux-amd64.go1.4.2.tar.gz
mv /tmp/google_auth_proxy-1.1.1.linux-amd64.go1.4.2/google_auth_proxy /opt/oauth2_proxy/oauth2_proxy

## Remove existing init.d config for elasticsearch
rm /etc/init.d/elasticsearch
rm /etc/init.d/logstash
update-rc.d elasticsearch remove
update-rc.d logstash remove

## Install upstart configuration
cp $FEATURE_ROOT/upstart-elasticsearch.conf /etc/init/elasticsearch.conf
cp $FEATURE_ROOT/upstart-logstash.conf /etc/init/logstash.conf
cp $FEATURE_ROOT/upstart-kibana4.conf /etc/init/kibana.conf
cp $FEATURE_ROOT/upstart-oauth2-proxy.conf  /etc/init/oauth2-proxy.conf
