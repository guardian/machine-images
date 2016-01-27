#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/configuration.sh

function HELP {
>&2 cat << EOF

  Usage: ${0} -d description

  This script creates a new incident in PagerDuty using a pre-configured
  PagerDuty API key.

    -d decription the incident description

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}
# Process options
while getopts d:h FLAG; do
  case $FLAG in
    d)
      ALERT_DESCRIPTION=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))
if [ -z "${ALERT_DESCRIPTION}" ]; then
    echo "Must specify an alert description"
    exit 1
fi

function current_ami() {
  echo $(curl -s --max-time 1 http://169.254.169.254/latest/meta-data/ami-id || echo "Unknown")
}

function instance_id() {
  echo $(curl -s --max-time 1 http://169.254.169.254/latest/meta-data/instance-id || echo "Unknown")
}

function trigger_incident() {
  local PAGERDUTY_SERVICE_KEY=${1}
  local DESCRIPTION=${2}
  local CLIENT=${3}
  curl --max-time 10 -H "Content-type: application/json" -X POST \
      -d "{
        \"service_key\": \"${PAGERDUTY_SERVICE_KEY}\",
        \"event_type\": \"trigger\",
        \"description\": \"${DESCRIPTION}\",
        \"client\": \"${CLIENT}\"
      }" \
      "https://events.pagerduty.com/generic/2010-04-15/create_event.json"
}

function main() {
  local DESCRIPTION=${1}
  # Load PagerDuty API key
  source "${PAGERDUTY_SERVICE_KEY_FILE}"
  if [ -z "${PAGERDUTY_SERVICE_KEY}" ]; then
    echo "No PagerDuty API key configured"
    exit 1
  fi
  local CLIENT="$(instance_id) running AMI $(current_ami)"
  trigger_incident "${PAGERDUTY_SERVICE_KEY}" "${DESCRIPTION}" "${CLIENT}"
}

main "${ALERT_DESCRIPTION}"
