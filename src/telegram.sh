#!/bin/bash

# Do some prep work
command -v jq >/dev/null 2>&1 || {
  echo >&2 "We require jq for this script to run, but it's not installed.  Aborting."
  exit 1
}
command -v git >/dev/null 2>&1 || {
  echo >&2 "We require git for this script to run, but it's not installed.  Aborting."
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo >&2 "We require curl for this script to run, but it's not installed.  Aborting."
  exit 1
}

# global config options
DRY_RUN=0
# translation version
VERSION="kjv"

# check if we have options
while :; do
  case $1 in
  --dry)
    DRY_RUN=1
    ;;
  -v | --version) # Takes an option argument; ensure it has been specified.
    if [ "$2" ]; then
      VERSION=$2
      shift
    else
      echo >&2 '"--version" requires a non-empty option argument.'
      exit 17
    fi
    ;;
  -v=?* | --version=?*)
    VERSION=${1#*=} # Delete everything up to "=" and assign the remainder.
    ;;
  -v= | --version=) # Handle the case of an empty --version=
    echo >&2 '"--version=" requires a non-empty option argument.'
    exit 17
    ;;
  *) # Default case: No more options, so break out of the loop.
    break ;;
  esac
  shift
done

#██████████████████████████████████████████████████████████████ DATE TODAY ███
# must set the time to Namibian :)
TODAY=$(TZ="Africa/Windhoek" date '+%A %d-%B, %Y')

#█████████████████████████████████████████████████████████████ SCRIPT PATH ███
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTURE_DIR="$DIR/../scripture/${VERSION}"

BOT_TOKEN="${BOT_TOKEN}"
CHANNEL_ID="${CHANNEL_ID}"

CHAT_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getChat?chat_id=${CHANNEL_ID}")

MESSAGE_ID=$(echo $CHAT_INFO | jq ".result.pinned_message.forward_from_message_id")
TEXT=$(echo $CHAT_INFO | jq ".result.pinned_message.text" | tr -d "\"")
DATE_STR=$(echo $TEXT | grep -oE "[A-Za-z]+ \d{2}-[A-Za-z]+, \d{4}$" | tr -d ",")
DATE_FORMATTED=$(date -d "${DATE_STR}" +"%m/%d/%y")

FILE_PATH="${SCRIPTURE_DIR}/${DATE_FORMATTED}/scripture.tg.id"

# check test behaviour
if (("$DRY_RUN" == 1)); then
  echo "===================================================="
  echo "Message ID: ${MESSAGE_ID}"
  echo "Path: ${FILE_PATH}"
  echo "===================================================="
elif [ ! -f "${FILE_PATH}" ] || [ "$(cat "${FILE_PATH}")" != "${MESSAGE_ID}" ]; then
  # update the default if this is kjv
  if [ "${VERSION}" = 'kjv' ]; then
    echo "${MESSAGE_ID}" >README.tg.id
  fi
  # make sure the folders exist
  mkdir -p "$(dirname "${FILE_PATH}")"

  # set ID
  echo "${MESSAGE_ID}" >"${FILE_PATH}"
  echo "${MESSAGE_ID}" >"${SCRIPTURE_DIR}/README.tg.id"

  # make sure to add new files and folders
  git add .
  git commit -am"${TODAY}"
  git push
fi

exit 0
