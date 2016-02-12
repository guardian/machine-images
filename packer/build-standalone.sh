#!/bin/bash

packer_file=${1}
build_name=${packer_file%%.*}

echo "Running packer with ${packer_file}" 1>&2
${PACKER_HOME}/packer build $FLAGS \
  -var "build_name=${build_name}" \
  -var "aws_access_key=${AWS_ACCESS_KEY_ID}" \
  -var "aws_access_key=${AWS_SECRET_ACCESS_KEY}"
  ${packer_file}
