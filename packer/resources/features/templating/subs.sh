#!/usr/bin/env bash
# This script contains functions that create a substitution map
# Note that some of the features of this script requires bash 4.3 or above.

# Usage: get_substitution_map [-f map-file] [-p stack] [-t]
#
# This script acquires key-value pairs from various sources and returns a bash
# format associative array.
#
#   -f map-file   Reads further values from the specified map-file (in key=value
#                 pairs).
#
#   -p stack      Reads the CFN stack parameters (these will appear with a
#                 prefix of 'param.').
#
#   -t            Reads the instance tags (these will appear with a prefix of
#                 'tag.'). If a tag exists called aws:cloudformation:stack-id
#                 (and the instance has the right permissions) then the stack
#                 parameters will be read as if the -p parameter had been passed
#                 with the value of the stack-id tag.

function props_to_aa {
  prefix=${1-}
  local -A PROPS
  while read -r line || [[ -n $line ]]; do
    local key=${prefix}${line%%=*}
    local value=${line#*=}
    if [ -n "${key}" -a -n "${value}" ]; then
      PROPS[${key}]=${value}
    fi
  done
  declare -p PROPS | sed -e 's/^declare -A [^=]*=//'
}

function empty_aa {
  echo "'()'"
}

function read_file {
  if [ -f ${1} ]; then
    >&2 echo "Reading ${1}"
    cat ${1} | props_to_aa
  else
    >&2 echo "File not found: ${1}"
    exit 1
  fi
}

function read_tags {
  local INSTANCE=$(ec2metadata --instance-id)
  >&2 echo "Reading AWS tags for ${INSTANCE}"
  local ret=0
  TAGS=`aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCE}"` || ret=$?
  if [ ${ret} == 0 ]; then
    (echo "${TAGS}" | jq -r '.Tags[] | [.Key, .Value] | join("=")') | props_to_aa "tag."
  else
    empty_aa
  fi
}

function read_parameters {
  local STACK DESC ret
  if echo "${1}" | grep -q 'tag.aws:cloudformation:stack-id'; then
    eval "local -A TAG_MAP=${1}"
    STACK=${TAG_MAP["tag.aws:cloudformation:stack-id"]}
  else
    STACK=${1}
  fi
  if [ -z "${STACK}" ]; then
    empty_aa
    return 0
  fi
  >&2 echo "Reading CFN stack parameters for stack '${STACK}'"
  ret=0
  DESC=`aws cloudformation describe-stacks --stack-name ${STACK}` || ret=$?
  if [ ${ret} == 0 ]; then
    (echo "${DESC}" | jq -r '.Stacks[0].Parameters[] | [.ParameterKey, .ParameterValue] | join("=")') | props_to_aa "param."
  else
    empty_aa
  fi
}

function merge_maps {
  local MAP_STRING=${1}
  eval "local -A MAP=${MAP_STRING}"
  shift

  while (( $# )); do
    local MAP2_STRING=${1}
    eval "local -A MAP2=${MAP2_STRING}"
    # Add keys from next map
    for K in "${!MAP2[@]}"; do
      MAP[$K]=${MAP2[$K]}
    done
    shift
  done

  declare -p MAP | sed -e 's/^declare -A [^=]*=//'
}

function get_substitution_map {
  local subs=$(empty_aa)
  local OPTIND FLAG

  # Process options
  while getopts itp:f:h FLAG; do
    case $FLAG in
      f)
        file_subs=$(read_file ${OPTARG})
        subs=$(eval merge_maps ${subs} ${file_subs})
        ;;
      t)
        tag_subs=$(read_tags)
        param_subs=$(eval read_parameters ${tag_subs})
        subs=$(eval merge_maps ${subs} ${tag_subs} ${param_subs})
        ;;
      p)
        param_subs=$(read_parameters $OPTARG)
        subs=$(eval merge_maps ${subs} ${param_subs})
        ;;
    esac
  done
  shift $((OPTIND-1))

  echo $subs
}
