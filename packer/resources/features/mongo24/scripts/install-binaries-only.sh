#!/usr/bin/env bash
set -e

S3_MIRROR_DOWNLOAD_URL_BASE="https://s3-eu-west-1.amazonaws.com/gu-mongodb-binary-mirror"
INTERNET_MIRROR_DOWNLOAD_URL_BASE="https://fastdl.mongodb.org/linux"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function HELP {
>&2 cat << EOF

  Usage: ${0} -v version

  This script downloads a specific version of the MongoDB binaries, but does
  not install any services or configuration files.

  This is useful when performing disaster recovery of a MongoDB cluster.

    -v version    The MongoDB version to install the binaries for.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts v:h FLAG; do
  case $FLAG in
    v)
      MONGO_VERSION=$OPTARG
    ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${MONGO_VERSION}" ]; then
    echo "Must specify a MongoDB version"
    exit 1
fi

function url_exists() {
  local URL=${1}
  curl --output /dev/null --silent --head --fail "${URL}"
}

function install_from_url() {
  local DOWNLOAD_URL=${1}
  local INSTALL_TARGET=${2}
  local TEMPORARY_FILE="/tmp/mongodb.tar.gz.$$"

  curl "${DOWNLOAD_URL}" --output "${TEMPORARY_FILE}"
  mkdir -p "${INSTALL_TARGET}"
  tar xzf "${TEMPORARY_FILE}" -C "${INSTALL_TARGET}" --strip-components 1
  rm "${TEMPORARY_FILE}"
}

S3_MONGO_DOWNLOAD_URL="${S3_MIRROR_DOWNLOAD_URL_BASE}/mongodb-linux-x86_64-${MONGO_VERSION}.tgz"
INTERNET_MONGO_DOWNLOAD_URL="${INTERNET_MIRROR_DOWNLOAD_URL_BASE}/mongodb-linux-x86_64-${MONGO_VERSION}.tgz"

TEMPORARY_FILE="/tmp/mongodb-${MONGO_VERSION}.tar.gz.$$"
INSTALL_TARGET="/opt/mongodb/${MONGO_VERSION}"

# Try installing from S3 first
if url_exists "${S3_MONGO_DOWNLOAD_URL}" ; then
  install_from_url "${S3_MONGO_DOWNLOAD_URL}" "${INSTALL_TARGET}"
else
  echo "Could not find MongoDB ${MONGO_VERSION} binaries in S3 mirror. Fetching from official MongoDB mirror."
  if url_exists "${INTERNET_MONGO_DOWNLOAD_URL}"; then
    install_from_url "${INTERNET_MONGO_DOWNLOAD_URL}" "${INSTALL_TARGET}"
  else
    echo "URL does not exist: ${INTERNET_MONGO_DOWNLOAD_URL}"
    exit 1
  fi
fi
