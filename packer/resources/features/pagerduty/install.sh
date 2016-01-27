#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/configuration.sh

function HELP {
>&2 cat << EOF

  Usage: ${0} -k PAGERDUTY_SERVICE_KEY

  This script installs a shared PagerDuty API key that can be used
  by alert.sh to trigger PagerDuty incidents.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}
# Process options
while getopts k:h FLAG; do
  case $FLAG in
    k)
      PAGERDUTY_SERVICE_KEY=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))
if [ -z "${PAGERDUTY_SERVICE_KEY}" ]; then
    echo "Must specify a PagerDuty API key"
    exit 1
fi

echo "PAGERDUTY_SERVICE_KEY=${PAGERDUTY_SERVICE_KEY}" > ${PAGERDUTY_SERVICE_KEY_FILE}
if [ $? -gt 0 ]; then
  echo "Could not write PagerDuty API key to file ${PAGERDUTY_SERVICE_KEY_FILE}"
  exit 2
fi
echo "Wrote PagerDuty API key to file ${PAGERDUTY_SERVICE_KEY_FILE}"
