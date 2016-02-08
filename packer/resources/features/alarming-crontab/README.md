# Alarming crontab feature

This feature adds a set of scripts that can be used to easily create a new
cronjob that will trigger an incident in PagerDuty if the command in the cronjob
 exits with a non-zero status.

The first step is to install a PagerDuty service key:

`/opt/features/pagerduty/install.sh -k PAGERDUTY_SERVICE_KEY `

Other scripts can then trigger an alert directly using:

`/opt/features/pagerduty/alert.sh -d "Alert description"`

Or add a new cronjob that is monitored:

`/opt/features/alarming-crontab/install.sh -u USER -d "My important backup job" -c '* * * * *  command to execute'`

This would result in the following crontab entry:

` * * * * *  command to execute || /opt/features/pagerduty/alert.sh -d "My important backup job"`
