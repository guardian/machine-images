#!/bin/bash
# Build packer AMI (on TeamCity host)

# die if any command fails
set -e

FLAGS='-color=false'
# set DEBUG flag if not in TeamCity
[ -z "${BUILD_NUMBER}" ] && FLAGS="-debug"

# set PACKER_HOME if it isn't already provided
[ -z "${PACKER_HOME}" ] && PACKER_HOME="/opt/packer"

# set build info to DEV if not in TeamCity
[ -z "${BUILD_NUMBER}" ] && BUILD_NUMBER="DEV"
[ -z "${BUILD_BRANCH}" ] && BUILD_BRANCH="DEV"
[ -z "${BUILD_VCS_REF}" ] && BUILD_VCS_REF="DEV"


# set BUILD_NUMBER to DEV if not in TeamCity
BUILD_NAME=${TEAMCITY_PROJECT_NAME}-${TEAMCITY_BUILDCONF_NAME}
[ -z "${TEAMCITY_BUILDCONF_NAME}" -o -z "${TEAMCITY_PROJECT_NAME}" ] && BUILD_NAME="unknown"

# ensure that we have AWS credentials (configure in TeamCity normally)
# note that we don't actually use them in the script, the packer command does
if [ -z "${AWS_ACCESS_KEY}" -o -z "${AWS_SECRET_KEY}" ]
then
  echo "AWS_ACCESS_KEY and AWS_SECRET_KEY environment variables must be set" 1>&2
  exit 1
fi

# Get all the account numbers of our AWS accounts
PRISM_JSON=$(curl -s "http://prism.gutools.co.uk/sources?resource=instance&origin.vendor=aws")
ACCOUNT_NUMBERS=$(echo ${PRISM_JSON} | jq '.data[].origin.accountNumber' | tr '\n' ',' | sed s/\"//g | sed s/,$//)
echo "Account numbers for AMI: $ACCOUNT_NUMBERS"

# Build the base Ubuntu image
echo "Running packer with base-ubuntu.json" 1>&2
PACKER_OUTPUT_FILE=$(mktemp packer-output.XXXXXX)
${PACKER_HOME}/packer build $FLAGS \
  -var "build_number=${BUILD_NUMBER}" -var "build_name=${BUILD_NAME}" \
  -var "build_branch=${BUILD_BRANCH}" -var "account_numbers=${ACCOUNT_NUMBERS}" \
  -var "build_vcs_ref=${BUILD_VCS_REF}" \
  base-ubuntu.json | tee ${PACKER_OUTPUT_FILE}

# Parse the Packer output to find the base Ubuntu image's AMI ID
BASE_AMI_ID=$(awk '/eu-west-1: ami-/ {print $2}' ${PACKER_OUTPUT_FILE} | head -n 1)
echo "Extracted AMI ID ${BASE_AMI_ID} from Packer output" 1>&2

# Build the customised Ubuntu images
for packer_file in `ls ubuntu/*.json`; do
  echo "Running packer with ${packer_file}" 1>&2
  ${PACKER_HOME}/packer build $FLAGS \
    -var "build_number=${BUILD_NUMBER}" -var "build_name=${BUILD_NAME}" \
    -var "build_branch=${BUILD_BRANCH}" -var "account_numbers=${ACCOUNT_NUMBERS}" \
    -var "build_vcs_ref=${BUILD_VCS_REF}" -var "euw1_source_ami=${BASE_AMI_ID}" \
    ${packer_file}
done

# If everything went well, clean up temp files
rm ${PACKER_OUTPUT_FILE}
