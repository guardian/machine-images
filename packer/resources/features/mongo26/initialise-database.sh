#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function HELP {
>&2 cat << EOF

  Usage: ${0} -f properties-file [-u ubuntu]

  This script will create a database and add a user and password

    -u user       [optional] the user to install the SSH keys for. Defaults to ubuntu.

    -f properties-file The file where the database and user credentials are stored

    -h            Displays this help message. No further functions are
                  performed.

EOF
exit 1
}

# Process options
while getopts u:f:h FLAG; do
  case $FLAG in
    u)
      SSH_USER=$OPTARG
      ;;
    f)
      FILE_NAME=$OPTARG
      ;;
    h)  #show help
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${FILE_NAME}" ]; then
    echo "Must specify the file (-f) to fetch database name and credentials"
    exit 1
fi

if [ -z "${SSH_USER}" ]; then
  SSH_USER="ubuntu"
fi

DATABASE_NAME=
DATABASE_USER=
DATABASE_PWD=

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

done < $FILE_NAME

echo $DATABASE_NAME
echo $DATABASE_USER
echo $DATABASE_PWD

if [ -z "${DATABASE_NAME}"  -o -z  "${DATABASE_USER}" -o -z "${DATABASE_PWD}" ]; then
    echo "One or more of database name, user and password is missing. Exiting."
    exit 1
fi

mongo <<EOF
use $DATABASE_NAME
db.createUser({user: "$DATABASE_USER", pwd: "$DATABASE_PWD", roles: ["readWrite"]});
EOF

echo "Done"
exit