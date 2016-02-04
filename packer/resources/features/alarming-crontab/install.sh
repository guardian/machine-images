#!/usr/bin/env bash
set -e
set -f

SCRIPTPATH=$( cd $(dirname $0/..) ; pwd -P )
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function HELP {
>&2 cat << EOF

  Usage: ${0} -u user -d description -c cron-definition

  This script adds a crontab entry for the given user and reports to
  PagerDuty in case the cronjob fails.

    -u user         the user to install crojob for.

    -d description  description of the cronjob

    -c              the cron definition.
                    E.g. "* * * * *  command to execute"

    -h              Displays this help message. No further functions are
                    performed.

EOF
exit 1
}
# Process options
while getopts u:c:d:h FLAG; do
  case $FLAG in
    u)
      CRONTAB_USER=$OPTARG
      ;;
    c)
      CRON_DEFINITION=$OPTARG
      ;;
    d)
      DESCRIPTION=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))
if [ -z "${CRONTAB_USER}" ]; then
    echo "Must specify a crontab user"
    exit 1
fi
if [ -z "${CRON_DEFINITION}" ]; then
    echo "Must specify a cron definition"
    exit 1
fi
if [ -z "${DESCRIPTION}" ]; then
    echo "Must specify a description"
    exit 1
fi

CRONTAB_TMP_FILE="/tmp/crontab-entry.$$"
crontab -l -u ${CRONTAB_USER} 1> ${CRONTAB_TMP_FILE} 2>/dev/null
echo "${CRON_DEFINITION} || ${SCRIPTPATH}/pagerduty/alert.sh -d \"${DESCRIPTION}\"" >> ${CRONTAB_TMP_FILE}
crontab -u ${CRONTAB_USER} ${CRONTAB_TMP_FILE}
rm ${CRONTAB_TMP_FILE}
