#!/usr/bin/env bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/key_functions.sh

function HELP {
>&2 cat << EOF

  Usage: ${0} -t team-github-name [-u ubuntu]

  This script installs keys stored in ~/github-team-keys/<team-name>/. Used as a fallback
  for when S3 is inaccessible.

    -u user       [optional] the user to install the SSH keys for. Defaults to ubuntu.

    -t team-name  The name of the team on github to have ssh access.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts u:t:h FLAG; do
  case $FLAG in
    u)
      SSH_USER=$OPTARG
      ;;
    t)
      GITHUB_TEAM_NAME=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))


if [ -z "${GITHUB_TEAM_NAME}" ]; then
    echo "Must specify a github team name"
    exit 1
fi

if [ -z "${SSH_USER}" ]; then
  SSH_USER="ubuntu"
fi

STORED_SSH_KEY_FILE=/opt/features/ssh-keys/github-team-keys/${GITHUB_TEAM_NAME}/authorized_keys
echo "Installing keys cached on ami creation from ${STORED_SSH_KEY_FILE}"


ensure_ssh_directory_exists "${SSH_USER}"
install_ssh_key_for_user "${SSH_USER}" "${STORED_SSH_KEY_FILE}"
ensure_key_file_permissions "${SSH_USER}"
