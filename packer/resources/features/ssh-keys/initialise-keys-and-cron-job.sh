#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function HELP {
>&2 cat << EOF

  Usage: ${0} -t team-github-name -b github-team-keys [-u ubuntu]

  This script runs install.sh to install keys from s3 and sets up a cron job to regularly
  update the installed ssh keys

    -u user       [optional] the user to install the SSH keys for. Defaults to ubuntu.

    -t team-name  The name of the team on github to have ssh access.

    -b github-keys-bucket The bucket containing team github keys

    -l Try to install keys cached in the machine image

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts u:t:b:lh FLAG; do
  case $FLAG in
    u)
      SSH_USER=$OPTARG
      ;;
    t)
      GITHUB_TEAM_NAME=$OPTARG
      ;;
    b)
      GITHUB_KEYS_BUCKET=$OPTARG
      ;;
    l)
      INSTALL_FROM_LOCAL=true
    ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${GITHUB_TEAM_NAME}" -o -z "${GITHUB_KEYS_BUCKET}" ]; then
    echo "Must specify a github team name and bucket"
    exit 1
fi

if [ -z "${SSH_USER}" ]; then
  SSH_USER="ubuntu"
fi

if [ ! -z "${INSTALL_FROM_LOCAL}" ]; then
    # we add || true to ensure that if the installation from local fails we continue to try to fetch keys from s3
    ${DIR}/install-from-local.sh -t ${GITHUB_TEAM_NAME} || true
fi

${DIR}/install.sh -t ${GITHUB_TEAM_NAME} -b ${GITHUB_KEYS_BUCKET}
cat > ${DIR}/ssh-keys-cron-job.txt << EOF
PATH=/bin:/usr/bin:/usr/local/bin
*/30 * * * * /opt/features/ssh-keys/install.sh -b ${GITHUB_KEYS_BUCKET} -t ${GITHUB_TEAM_NAME} > ~${SSH_USER}/last-ssh-update.log 2>&1
EOF
echo "Initialising cron job"
crontab -u ${SSH_USER} ${DIR}/ssh-keys-cron-job.txt
