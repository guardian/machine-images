#!/bin/bash
#
# Install ELK stack
#
# This script must be run as root
set -e

FEATURE_ROOT=/opt/features/elk-stack

KIBANA_VERSION=4.1.1

## Add repositories we are going to use
wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb http://packages.elastic.co/elasticsearch/1.7/debian stable main" > /etc/apt/sources.list.d/elasticsearch.list
echo "deb http://packages.elastic.co/logstash/1.5/debian stable main" > /etc/apt/sources.list.d/logstash.list

## Update index and install packages
apt-get update
apt-get --yes --force-yes install ruby ruby-dev python-pip \
    golang libwww-perl libdatetime-perl nginx logstash elasticsearch

## Install Cloudwatch monitoring scripts
wget "http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip" -O /tmp/CloudWatchMonitoringScripts.zip
unzip /tmp/CloudWatchMonitoringScripts.zip -d /tmp/
rm /tmp/CloudWatchMonitoringScripts.zip
mv /tmp/aws-scripts-mon /usr/local/

# Add disk space cron job
crontab -u root - << EOM
*/5 * * * * /usr/local/aws-scripts-mon/mon-put-instance-data.pl --disk-space-util --mem-util --disk-path=/ --disk-path=/data --auto-scaling --from-cron
EOM

## Install Elasticsearch plugins
/usr/share/elasticsearch/bin/plugin --install elasticsearch/elasticsearch-cloud-aws/2.7.0
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
cp $FEATURE_ROOT/elasticsearch-template.json /etc/logstash/elasticsearch-template.json
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
cp $FEATURE_ROOT/systemd-kibana4.service /etc/systemd/system/kibana.service

# Install Kibana ES index backup script
cp $FEATURE_ROOT/kibana-index-backup /etc/cron.daily/kibana-index-backup
chmod +x /etc/cron.daily/kibana-index-backup

# Install Google Auth Proxy
mkdir /opt/oauth2_proxy
useradd -M -r -U -s /bin/false -d /opt/oauth2_proxy oauth2-proxy
cd /tmp
wget https://github.com/bitly/oauth2_proxy/releases/download/v2.0/oauth2_proxy-2.0.linux-amd64.go1.4.2.tar.gz
tar -zxf oauth2_proxy-2.0.linux-amd64.go1.4.2.tar.gz
mv /tmp/oauth2_proxy-2.0.linux-amd64.go1.4.2/oauth2_proxy /opt/oauth2_proxy/oauth2_proxy
cp $FEATURE_ROOT/systemd-oauth2-proxy.service /etc/systemd/system/oauth2-proxy.service
cp $FEATURE_ROOT/sysconfig-oauth2-proxy /etc/default/oauth2-proxy

## Install NGINX config
cp $FEATURE_ROOT/nginx-config /etc/nginx/sites-available/default
