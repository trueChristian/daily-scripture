#!/bin/bash

# Do some prep work
command -v git >/dev/null 2>&1 || {
  echo >&2 "We require git for this script to run, but it's not installed.  Aborting."
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo >&2 "We require curl for this script to run, but it's not installed.  Aborting."
  exit 1
}

# global config options
DRYRUN=0

# check if we have options
while :; do
  case $1 in
  --dry)
    DRYRUN=1
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

#███████████████████████████████████████████████████████████████ SCRIPTURE ███
SORTED="$DIR/SCRIPTURE"
USED="$DIR/SCRIPTURE_USED"
TMP="$DIR/.TMP"

#██████████████████████████████████████████████████████████████████ RANDOM ███
# set a random temp file
sort -R -k1 -b "${SORTED}" >"${TMP}"
# get the first line
VERSE=$(head -n 1 "${TMP}")
# test behaviour
if (("$DRYRUN" == 1)); then
  echo "selected: $VERSE"
else
  # remove the verse
  sed -i -e '1,1d' "${TMP}"
  # add to used verses
  [ -f "${USED}" ] && echo "$VERSE" >>"${USED}" || echo "$VERSE" >"${USED}"
fi

#█████████████████████████████████████████████████████ SIX MONTH RETENTION ███
# check test behaviour
if (("$DRYRUN" == 0)); then
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

#███████████████████████████████████████████████████████████████ SORT BACK ███
# check test behaviour
if (("$DRYRUN" == 0)); then
  # store back for next time
  sort -h -b -k1 "${TMP}" >"${SORTED}"
fi
# remove the temp file
rm -f "${TMP}"

#███████████████████████████████████████████████████████ GET SCRIPTURE TEXT ███
# Get the verses from the getBible API
VERSES=$(bash <(curl -s https://raw.githubusercontent.com/getbible/getverse/master/src/chapter.sh) "${VERSE}")

#███████████████████████████████████████████████████████ GET SCRIPTURE NAME ███
# Get the verses name from the getBible API
NAME=$(bash <(curl -s https://raw.githubusercontent.com/getbible/getverse/master/src/name.sh) "${VERSE}")

#████████████████████████████████████████████ SET TODAY'S SCRIPTURE IN HTML ███
HTML="<h4>${NAME}</h4>
<p>${VERSES//$'\n'/ }</p>
<p><a id=\"daily-scripture-link\" href=\"https://t.me/daily_scripture\">${TODAY}</a></p>"

#████████████████████████████████████████ SET TODAY'S SCRIPTURE IN MARKDOWN ███
MARKDOWN="#### ${NAME}

${VERSES//$'\n'/ }

[${TODAY}](https://t.me/s/daily_scripture)"

#███████████████████████████████████████████████████████████████ SET FILES ███

# check test behaviour
if (("$DRYRUN" == 1)); then
  echo "${HTML}"
  echo "----------------------------------------------------"
  echo "${MARKDOWN}"
else
  echo "${HTML}" >README.html
  echo "${MARKDOWN}" >README.md

  git commit -am"${TODAY}"
  git push
fi

exit 0
