#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/key_functions.sh

function HELP {
>&2 cat << EOF

  Usage: ${0} -k key-s3-url [-u ubuntu]

  This script retrieves public SSH keys from AWS S3 and overwrites
  ~/.ssh/authorized_keys for the defined user. Either an s3 url or
  a team github keys bucket and team name must be provided.

    -k key-s3-url The full S3 URL of the public SSH keys (e.g. s3://mybucket/ssh-keys.txt).

    -u user       [optional] the user to install the SSH keys for. Defaults to ubuntu.

    -t team-name  The name of the team on github to have ssh access.

    -b github-keys-bucket The bucket containing team github keys

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts k:u:t:b:h FLAG; do
  case $FLAG in
    k)
      S3_KEY_URL=$OPTARG
      ;;
    u)
      SSH_USER=$OPTARG
      ;;
    t)
      GITHUB_TEAM_NAME=$OPTARG
      ;;
    b)
      GITHUB_KEYS_BUCKET=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))
TEAM_BUCKET_MODE="false"
if [[ -z "${S3_KEY_URL}" ]] ; then
    if [ -z "${GITHUB_TEAM_NAME}" -o -z "${GITHUB_KEYS_BUCKET}" ]; then
        echo "Must specify an S3 URL or a github team name and bucket"
        exit 1
    else
        TEAM_BUCKET_MODE="true"
        S3_KEY_URL=s3://$GITHUB_KEYS_BUCKET/$GITHUB_TEAM_NAME/authorized_keys
        echo "Generated key url: ${S3_KEY_URL}"
    fi
fi

if [ -z "${SSH_USER}" ]; then
  SSH_USER="ubuntu"
fi

TEMPORARY_SSH_KEY_FILE="/tmp/authorized_keys.$$"

echo "Installing keys from S3"
ensure_ssh_directory_exists "${SSH_USER}"
check_ssh_key_url_is_valid "${S3_KEY_URL}"
fetch_ssh_key_from_url "${S3_KEY_URL}" "${TEMPORARY_SSH_KEY_FILE}"
install_ssh_key_for_user "${SSH_USER}" "${TEMPORARY_SSH_KEY_FILE}"
ensure_key_file_permissions "${SSH_USER}"
