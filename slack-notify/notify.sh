#!/usr/bin/env bash
# Post a status message to Slack with chat.postMessage.
#
# Generic on purpose: everything comes from the environment, so the action and
# systemd units run the same script.
#
#   SLACK_TOKEN | SLACK_TOKEN_FILE  bot token (xoxb-...); the file form suits
#                                   systemd LoadCredential
#   SLACK_CHANNEL                   "#updates" or a channel ID
#   NOTIFY_STATUS                   success | failure | cancelled | info
#   NOTIFY_TITLE                    plain text; becomes the notification preview
#   NOTIFY_FIELDS                   optional; one "Label: value" per line, value is mrkdwn
#   NOTIFY_CONTEXT                  optional; one mrkdwn line
#   NOTIFY_THREAD_TS                optional; reply in this thread
#   NOTIFY_BROADCAST                optional; "true" or "1" also shows a reply in the channel
#   NOTIFY_DRY_RUN                  optional; print the payload and exit without calling Slack
#   SLACK_API_URL                   optional; override the endpoint (tests)
#
# On success prints ts= and channel=, and writes them to $GITHUB_OUTPUT when set.
set -euo pipefail

: "${SLACK_CHANNEL:?SLACK_CHANNEL is required}"
: "${NOTIFY_STATUS:?NOTIFY_STATUS is required}"
: "${NOTIFY_TITLE:?NOTIFY_TITLE is required}"

case "$NOTIFY_STATUS" in
success) emoji=':white_check_mark:' color='#2EB67D' ;;
failure) emoji=':x:' color='#CC0000' ;;
cancelled) emoji=':warning:' color='#ECB22E' ;;
info) emoji=':information_source:' color='#439FE0' ;;
*)
  echo "NOTIFY_STATUS must be success, failure, cancelled or info (got: $NOTIFY_STATUS)" >&2
  exit 2
  ;;
esac

# Every value reaches the payload through --arg, never through string concatenation.
payload=$(
  jq -n \
    --arg channel "$SLACK_CHANNEL" \
    --arg emoji "$emoji" \
    --arg color "$color" \
    --arg title "$NOTIFY_TITLE" \
    --arg fields "${NOTIFY_FIELDS:-}" \
    --arg context "${NOTIFY_CONTEXT:-}" \
    --arg thread_ts "${NOTIFY_THREAD_TS:-}" \
    --arg broadcast "${NOTIFY_BROADCAST:-}" '
    def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");

    ($fields | split("\n") | map(select(test("\\S")))
      | map(capture("^(?<label>.+?): (?<value>.*)$") // error("malformed field (want \"Label: value\"): \(.)"))
      | map({type: "mrkdwn", text: "*\(.label)*\n\(.value)"})) as $fields
    | ([
        (if ($fields | length) > 0 then {type: "section", fields: $fields} else empty end),
        (if $context != "" then {type: "context", elements: [{type: "mrkdwn", text: $context}]} else empty end)
      ]) as $blocks
    | {
        channel: $channel,
        text: "\($emoji) \($title | esc)",
        unfurl_links: false,
        unfurl_media: false
      }
    + (if ($blocks | length) > 0 then {attachments: [{color: $color, blocks: $blocks}]} else {} end)
    + (if $thread_ts != "" then {thread_ts: $thread_ts} else {} end)
    + (if $thread_ts != "" and ($broadcast | test("^(1|true)$")) then {reply_broadcast: true} else {} end)
  '
)

write_output() {
  if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf '%s\n' "$@" >>"$GITHUB_OUTPUT"
  fi
}

if [[ -n ${NOTIFY_DRY_RUN:-} ]]; then
  printf '%s\n' "$payload"
  # Multiline output needs the delimiter form.
  delim="payload_$RANDOM$RANDOM$RANDOM"
  write_output "payload<<$delim" "$payload" "$delim"
  exit 0
fi

if [[ -n ${SLACK_TOKEN_FILE:-} ]]; then
  token=$(<"$SLACK_TOKEN_FILE")
else
  token=${SLACK_TOKEN:-}
fi
token=$(printf '%s' "$token" | tr -d '[:space:]')
if [[ -z $token ]]; then
  echo "Slack token is empty: set SLACK_TOKEN or SLACK_TOKEN_FILE" >&2
  exit 2
fi

# The token goes in through a config file descriptor so it never shows in the
# process list.
response=$(
  curl -sS --fail-with-body --max-time 30 --retry 3 \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
    -H 'Content-Type: application/json; charset=utf-8' \
    --data-binary "$payload" \
    "${SLACK_API_URL:-https://slack.com/api/chat.postMessage}"
) || {
  printf '%s\n' "$response" >&2
  exit 1
}

if [[ $(jq -r '.ok // false' <<<"$response" 2>/dev/null || echo false) != true ]]; then
  jq -r '"slack: \(.error // "unknown_error")", ((.response_metadata.messages // [])[] | "  \(.)")' \
    <<<"$response" >&2 2>/dev/null || printf 'slack: unparseable response: %s\n' "$response" >&2
  exit 1
fi

ts=$(jq -r '.ts' <<<"$response")
channel=$(jq -r '.channel' <<<"$response")
echo "ts=$ts"
echo "channel=$channel"
write_output "ts=$ts" "channel=$channel"
