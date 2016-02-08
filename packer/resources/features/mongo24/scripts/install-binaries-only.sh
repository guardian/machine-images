#!/usr/bin/env bash
set -e

MONGO_DOWNLOAD_URL_BASE="http://downloads.mongodb.org/linux"

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

MONGO_DOWNLOAD_URL="${MONGO_DOWNLOAD_URL_BASE}/mongodb-linux-x86_64-${MONGO_VERSION}.tgz"
TEMPORARY_FILE="/tmp/mongodb-${MONGO_VERSION}.tar.gz.$$"
INSTALL_TARGET="/opt/mongodb/${MONGO_VERSION}"

if curl --output /dev/null --silent --head --fail "${MONGO_DOWNLOAD_URL}"; then
  curl "${MONGO_DOWNLOAD_URL}" --output "${TEMPORARY_FILE}"
  mkdir -p "${INSTALL_TARGET}"
  tar xzf "${TEMPORARY_FILE}" -C "${INSTALL_TARGET}" --strip-components 1
else
  echo "URL does not exist: ${MONGO_DOWNLOAD_URL}"
  exit 1
fi
