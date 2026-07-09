#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ==============================================================================
# Get today's Telegram channel post ID and store it in scripture.tg.id
#
# Required environment:
#   BOT_TOKEN   Telegram bot token
#   CHANNEL_ID  Telegram channel id, e.g. -1001234567890 or @public_channel
#
# Optional:
#   --dry
#   -v|--version kjv
# ==============================================================================

DRY_RUN=0
VERSION="kjv"
TZ_NAME="Africa/Windhoek"

while (($#)); do
	case "$1" in
		--dry|--dry-run)
			DRY_RUN=1
			;;
		-v|--version)
			if [[ -n "${2:-}" ]]; then
				VERSION="$2"
				shift
			else
				echo >&2 '"--version" requires a non-empty option argument.'
				exit 17
			fi
			;;
		-v=*|--version=*)
			VERSION="${1#*=}"
			if [[ -z "$VERSION" ]]; then
				echo >&2 '"--version=" requires a non-empty option argument.'
				exit 17
			fi
			;;
		*)
			echo >&2 "Unknown option: $1"
			exit 17
			;;
	esac

	shift
done

command -v jq >/dev/null 2>&1 || {
	echo >&2 "We require jq for this script to run, but it's not installed. Aborting."
	exit 1
}

command -v git >/dev/null 2>&1 || {
	echo >&2 "We require git for this script to run, but it's not installed. Aborting."
	exit 1
}

command -v curl >/dev/null 2>&1 || {
	echo >&2 "We require curl for this script to run, but it's not installed. Aborting."
	exit 1
}

command -v date >/dev/null 2>&1 || {
	echo >&2 "We require date for this script to run, but it's not installed. Aborting."
	exit 1
}

BOT_TOKEN="${BOT_TOKEN:-}"
CHANNEL_ID="${CHANNEL_ID:-}"

if [[ -z "$BOT_TOKEN" ]]; then
	echo >&2 "BOT_TOKEN is not set."
	exit 1
fi

if [[ -z "$CHANNEL_ID" ]]; then
	echo >&2 "CHANNEL_ID is not set."
	exit 1
fi

TODAY_YMD="$(TZ="$TZ_NAME" date '+%F')"
TODAY_TITLE="$(TZ="$TZ_NAME" date '+%A %d-%B, %Y')"
TODAY_PATH_DATE="$(TZ="$TZ_NAME" date '+%m/%d/%y')"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$DIR" rev-parse --show-toplevel)"

SCRIPTURE_DIR="${REPO_ROOT}/scripture/${VERSION}"
FILE_PATH="${SCRIPTURE_DIR}/${TODAY_PATH_DATE}/scripture.tg.id"

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"

# Get the latest pending updates.
#
# offset=-100 asks Telegram for the last 100 pending updates and forgets older
# pending updates. Since this script only cares about today's daily post, this
# keeps the bot update queue clean.
UPDATES_JSON="$(
	curl -fsS \
		--retry 3 \
		--retry-delay 2 \
		--connect-timeout 15 \
		--max-time 45 \
		-H 'Content-Type: application/json' \
		-d '{"offset":-100,"limit":100,"timeout":0,"allowed_updates":["channel_post","edited_channel_post"]}' \
		"${API_URL}/getUpdates"
)"

OK="$(printf '%s' "$UPDATES_JSON" | jq -r '.ok')"

if [[ "$OK" != "true" ]]; then
	DESCRIPTION="$(printf '%s' "$UPDATES_JSON" | jq -r '.description // "Unknown Telegram API error"')"

	echo >&2 "Telegram getUpdates failed: ${DESCRIPTION}"
	echo >&2
	echo >&2 "Common cause: the bot has a webhook configured."
	echo >&2 "Check it with:"
	echo >&2 "  curl -s \"${API_URL}/getWebhookInfo\" | jq"
	echo >&2
	echo >&2 "If this bot is only used by this script, remove the webhook with:"
	echo >&2 "  curl -s \"${API_URL}/deleteWebhook\" | jq"

	exit 1
fi

# CHANNEL_ID can be:
#   - numeric id: -1001234567890
#   - public username: @channelname
#
# This filter accepts both.
MESSAGE_ID="$(
	printf '%s' "$UPDATES_JSON" \
		| jq -r \
			--arg channel_id "$CHANNEL_ID" \
			--arg today "$TODAY_YMD" \
			--arg tz "$TZ_NAME" '
				[
					.result[]
					| (.channel_post // .edited_channel_post // empty) as $message
					| select(
						(($message.chat.id // "") | tostring) == $channel_id
						or
						(
							($channel_id | startswith("@"))
							and
							(
								(($message.chat.username // "") | ascii_downcase)
								==
								(($channel_id | ltrimstr("@")) | ascii_downcase)
							)
						)
					)
					| select(($message.date | strflocaltime("%Y-%m-%d")) == $today)
					| {
						message_id: $message.message_id,
						date: $message.date
					}
				]
				| sort_by(.date, .message_id)
				| last
				| .message_id // empty
			'
)"

if [[ -z "$MESSAGE_ID" || "$MESSAGE_ID" == "null" ]]; then
	echo >&2 "No Telegram channel post found for today: ${TODAY_YMD}"
	echo >&2
	echo >&2 "This usually means one of these:"
	echo >&2 "  1. Today's post has not been published yet."
	echo >&2 "  2. The bot is not in the channel."
	echo >&2 "  3. The bot is not allowed to receive channel posts."
	echo >&2 "  4. Another webhook/service already consumed the update."
	echo >&2 "  5. The update is older than Telegram's pending update window."
	exit 1
fi

if [[ ! "$MESSAGE_ID" =~ ^[0-9]+$ ]]; then
	echo >&2 "Invalid Telegram message ID received: ${MESSAGE_ID}"
	exit 1
fi

if ((DRY_RUN == 1)); then
	echo "===================================================="
	echo "Today:      ${TODAY_TITLE}"
	echo "Date path:  ${TODAY_PATH_DATE}"
	echo "Message ID: ${MESSAGE_ID}"
	echo "Path:       ${FILE_PATH}"
	echo "===================================================="
	exit 0
fi

mkdir -p "$(dirname "$FILE_PATH")"

CURRENT_ID=""

if [[ -f "$FILE_PATH" ]]; then
	CURRENT_ID="$(tr -d '[:space:]' < "$FILE_PATH")"
fi

if [[ "$CURRENT_ID" == "$MESSAGE_ID" ]]; then
	echo "Today's Telegram message ID is already up to date: ${MESSAGE_ID}"
	exit 0
fi

printf '%s\n' "$MESSAGE_ID" > "$FILE_PATH"
printf '%s\n' "$MESSAGE_ID" > "${SCRIPTURE_DIR}/README.tg.id"

if [[ "$VERSION" == "kjv" ]]; then
	printf '%s\n' "$MESSAGE_ID" > "${REPO_ROOT}/README.tg.id"
fi

git -C "$REPO_ROOT" add \
	"$FILE_PATH" \
	"${SCRIPTURE_DIR}/README.tg.id"

if [[ "$VERSION" == "kjv" ]]; then
	git -C "$REPO_ROOT" add "${REPO_ROOT}/README.tg.id"
fi

if git -C "$REPO_ROOT" diff --cached --quiet; then
	echo "No git changes to commit."
	exit 0
fi

git -C "$REPO_ROOT" commit -m "$TODAY_TITLE"
git -C "$REPO_ROOT" push

echo "Saved today's Telegram message ID: ${MESSAGE_ID}"

exit 0
