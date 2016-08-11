#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function HELP {
>&2 cat << EOF

  Usage: ${0} -b bucket

  This script will create a database and add a user and password


    -b bucket     The S3 bucket to download the artifact from.
                  Note that the URL will be generated automatically from the
                  stack, stage and app tags.

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts b:h FLAG; do
  case $FLAG in
    b)
      BUCKET=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
source ${SCRIPTPATH}/../templating/metadata.sh
eval declare -A SUBS=$(get_metadata -t)

function sub {
  echo ${SUBS[${1}]}
}
REGION=$(get_region)
STACK=$(sub "tag.Stack")
STAGE=$(sub "tag.Stage")
APP=$(sub "tag.App")


if [ -z "${BUCKET}" ]; then
    echo "Must specify the bucket (-b) containing file holding the to fetch database name and credentials"
    exit 1
fi

PROPERTIES_FILE="${DIR}/tmp.properties"

aws s3 cp "s3://${BUCKET}/${STACK}/${APP}/${STAGE}.properties" ${PROPERTIES_FILE} --region ${REGION}

DATABASE_NAME=
DATABASE_USER=
DATABASE_PWD=
ADMIN_USER=
ADMIN_PWD=

# read file line by line and populate the array
while IFS='=' read -r k v; do
   if [ "$k" == "mongo.database.name" ]
   then
    DATABASE_NAME=$v
   fi
   if [ "$k" == "mongo.database.username" ]
   then
    DATABASE_USER=$v
   fi
   if [ "$k" == "mongo.database.password" ]
   then
    DATABASE_PWD=$v
   fi
   if [ "$k" == "mongo.admin.username" ]
   then
    ADMIN_USER=$v
   fi
   if [ "$k" == "mongo.admin.password" ]
   then
    ADMIN_PWD=$v
   fi
done < $PROPERTIES_FILE

if [ -z "${DATABASE_NAME}"  -o -z  "${DATABASE_USER}" -o -z "${DATABASE_PWD}" -o -z "${ADMIN_USER}" -o -z "${ADMIN_PWD}"]; then
    echo "One or more of properties is missing, check script. Exiting."
    exit 1
fi

# Install the config file to /etc/mongod.conf
CONFIG_FILE=/etc/mongod.conf
cp ${CONFIG_FILE} ${CONFIG_FILE}.original
install -m 644 -o root -g root ${SCRIPTPATH}/mongod.conf ${CONFIG_FILE}

# chown the data and log
chown mongodb /var/lib/mongodb
chown mongodb:mongodb /var/log/mongodb

# Restart mongod
service mongod restart

sleep 5

mongo <<EOF
use admin
db.createUser({ user: "$ADMIN_USER", pwd: "$ADMIN_PWD", roles: ["userAdminAnyDatabase"] })
db.auth("$ADMIN_USER", "$ADMIN_PWD")
db.runCommand({authSchemaUpgrade: 1 });
use $DATABASE_NAME
db.createUser({user: "$DATABASE_USER", pwd: "$DATABASE_PWD", roles: ["readWrite"]});
EOF

rm $PROPERTIES_FILE

echo "Done"
exit