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
# scripture
TODAY_S_SCRIPTURE=''

# check if we have options
while :; do
  case $1 in
  --dry)
    DRY_RUN=1
    ;;
  -s | --scripture) # Takes an option argument; ensure it has been specified.
    if [ "$2" ]; then
      TODAY_S_SCRIPTURE=$2
      shift
    else
      echo >&2 '"--scripture" requires a non-empty option argument.'
      exit 17
    fi
    ;;
  -s=?* | --scripture=?*)
    TODAY_S_SCRIPTURE=${1#*=} # Delete everything up to "=" and assign the remainder.
    ;;
  -s= | --scripture=) # Handle the case of an empty --scripture=
    echo >&2 '"--scripture=" requires a non-empty option argument.'
    exit 17
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
TODAY_FOLDER=$(TZ="Africa/Windhoek" date '+%D')

#█████████████████████████████████████████████████████████████ SCRIPT PATH ███
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#███████████████████████████████████████████████████████████████ SCRIPTURE ███
SORTED="$DIR/SCRIPTURE"
USED="$DIR/SCRIPTURE_USED"
TMP="$DIR/.TMP"
SCRIPTURE_DIR="$DIR/../scripture/${VERSION}/${TODAY_FOLDER}"
VERSION_DIR="$DIR/../scripture/${VERSION}"

#█████████████████████████████████████████████████ GET SCRIPTURE FOR TODAY ███
# only load if not already given
if [ -z "${TODAY_S_SCRIPTURE}" ]; then
  #████████████████████████████████████████████████████████████████ RANDOM ███
    # set a random temp file
    sort -R -k1 -b "${SORTED}" >"${TMP}"
    # get the first line
    TODAY_S_SCRIPTURE=$(head -n 1 "${TMP}")
    # only if not a test
    if (("$DRY_RUN" == 0)); then
      # remove the verse
      sed -i -e '1,1d' "${TMP}"
      # add to used verses
      [ -f "${USED}" ] && echo "$TODAY_S_SCRIPTURE" >>"${USED}" || echo "$TODAY_S_SCRIPTURE" >"${USED}"
    fi

  #███████████████████████████████████████████████████ SIX MONTH RETENTION ███
  # check test behaviour
  if (("$DRY_RUN" == 0)); then
    # count the number of verse in used file
    LINES_NR=$(wc -l <"${USED}")
    if [ "$LINES_NR" -gt 182 ]; then
      # get the first line
      VERSE_BACK=$(head -n 1 "${USED}")
      # remove the verse
      sed -i -e '1,1d' "${USED}"
      # add add back to the pile
      echo "$VERSE_BACK" >>"${TMP}"
    fi
  fi

  #█████████████████████████████████████████████████████████████ SORT BACK ███
  # check test behaviour
  if (("$DRY_RUN" == 0)); then
    # store back for next time
    sort -h -b -k1 "${TMP}" >"${SORTED}"
  fi
  # remove the temp file
  rm -f "${TMP}"
fi

#█████████████████████████████████████████████ SHOW WHAT SCRIPTURE SELECTED ███
if (("$DRY_RUN" == 1)); then
  echo "selected: $TODAY_S_SCRIPTURE"
  echo "version: $VERSION"
fi

#███████████████████████████████████████████████████████ GET SCRIPTURE TEXT ███
# Get the verses from the getBible API
TODAY_S_SCRIPTURE_TEXT=$(bash <(curl -s https://raw.githubusercontent.com/getbible/getverse/master/src/chapter.sh) -s="\"${TODAY_S_SCRIPTURE}\"" -v="${VERSION}" )

#███████████████████████████████████████████████████████ GET SCRIPTURE NAME ███
# Get the verses name from the getBible API
NAME=$(bash <(curl -s https://raw.githubusercontent.com/getbible/getverse/master/src/name.sh) -s="\"${TODAY_S_SCRIPTURE}\"" -v="${VERSION}" )

#████████████████████████████████████████████ SET TODAY'S SCRIPTURE IN HTML ███
HTML="<strong>${NAME}</strong><br />
${TODAY_S_SCRIPTURE_TEXT//$'\n'/ }<br /><br />
<a id=\"daily-scripture-link\" href=\"https://t.me/s/daily_scripture\">${TODAY}</a>"

#████████████████████████████████████████████ SET TODAY'S SCRIPTURE IN JSON ███
# convert text to json
IFS=$'\n'; TODAY_S_SCRIPTURE_ARRAY=( $TODAY_S_SCRIPTURE_TEXT )
TODAY_S_SCRIPTURE_JSON='[]'
for line in "${TODAY_S_SCRIPTURE_ARRAY[@]}"; do
  # shellcheck disable=SC2001
  text_nr=$(echo "${line}" | sed 's@^[^0-9]*\([0-9]\+\).*@\1@')
  text="${line#$text_nr }"
  TODAY_S_SCRIPTURE_JSON="$(
      jq <<<"$TODAY_S_SCRIPTURE_JSON" -c \
        --arg nr "$text_nr" \
        --arg text "$text" '
  			. += [{
  				nr: $nr,
  				text: $text
  			}]
  		'
    )"
done
# build the json object
JSON='{}';  JSON="$(
    jq <<<"$JSON" -c \
      --arg name "${NAME}" \
      --argjson scripture "${TODAY_S_SCRIPTURE_JSON}"  \
      --arg version "${VERSION}" \
      --arg date "${TODAY}" \
      --arg telegram "daily_scripture" \
      --arg source "https://github.com/trueChristian/daily-scripture" '
      {
        name: $name,
        scripture: $scripture,
        version: $version,
        date: $date,
        telegram: $telegram,
        source: $source
      }
    '
  )"

#██████████████████████████████████████████████ SET TODAY'S SCRIPTURE IN TG ███
TG="<strong>${NAME}</strong>
${TODAY_S_SCRIPTURE_TEXT//$'\n'/ }

<a id=\"daily-scripture-link\" href=\"https://t.me/daily_scripture\">${TODAY}</a>"

#████████████████████████████████████████ SET TODAY'S SCRIPTURE IN MARKDOWN ███
MARKDOWN="**${NAME}**

${TODAY_S_SCRIPTURE_TEXT//$'\n'/ }

[${TODAY}](https://t.me/s/daily_scripture)"

#███████████████████████████████████████████████████████████████ SET FILES ███

# check test behaviour
if (("$DRY_RUN" == 1)); then
  echo "===================================================="
  echo "selected: ${TODAY_S_SCRIPTURE}"
  echo "version: ${VERSION}"
  echo "===================================================="
  echo "${HTML}"
  echo "----------------------------------------------------"
  jq <<<"$JSON" -S .
  echo "----------------------------------------------------"
  echo "${TG}"
  echo "----------------------------------------------------"
  echo "${MARKDOWN}"
else
  # update the default if this is kjv
  if [ "${VERSION}" = 'kjv' ]; then
    echo "${HTML}" >README.html
    jq <<<"$JSON" -S . >README.json
    echo "${TG}" >README.tg
    echo "${MARKDOWN}" >README.md
    echo "${TODAY_S_SCRIPTURE}" >README.today
  fi
  # make sure the folders exist
  mkdir -p "${SCRIPTURE_DIR}"
  # set today's README scripture
  echo "${HTML}" >"${VERSION_DIR}/README.html"
  jq <<<"$JSON" -S . >"${VERSION_DIR}/README.json"
  echo "${TG}" >"${VERSION_DIR}/README.tg"
  echo "${MARKDOWN}" >"${VERSION_DIR}/README.md"
  echo "${TODAY_S_SCRIPTURE}" >"${VERSION_DIR}/README.today"
  # set today's verse to persistent state
  echo "${HTML}" >"${SCRIPTURE_DIR}/scripture.html"
  jq <<<"$JSON" -S . >"${SCRIPTURE_DIR}/scripture.json"
  echo "${TG}" >"${SCRIPTURE_DIR}/scripture.tg"
  echo "${MARKDOWN}" >"${SCRIPTURE_DIR}/scripture.md"
  echo "${TODAY_S_SCRIPTURE}" >"${SCRIPTURE_DIR}/scripture.today"
  # make sure to add new files and folders
  git add .
  git commit -am"${TODAY}"
  git push
fi

exit 0
