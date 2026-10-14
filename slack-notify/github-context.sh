#!/usr/bin/env bash
# Derive the NOTIFY_* variables for a GitHub Actions run and write them to
# $GITHUB_ENV (stdout when unset), for notify.sh to read.
#
# Reads the action's inputs as INPUT_STATUS, INPUT_TITLE, INPUT_TITLE_PREFIX,
# INPUT_FIELDS, INPUT_FAILED_JOBS and INPUT_GITHUB_TOKEN, plus the usual
# GITHUB_* variables. Event data comes from $GITHUB_EVENT_PATH, never from
# workflow expressions, so a quote or backslash in a PR title can't reach the
# payload as anything but text.
set -euo pipefail

out=${GITHUB_ENV:-/dev/stdout}
server=${GITHUB_SERVER_URL:-https://github.com}
repo=${GITHUB_REPOSITORY:-unknown/unknown}
repo_url=$server/$repo
sha=${GITHUB_SHA:-}
short_sha=${sha:0:7}
event_name=${GITHUB_EVENT_NAME:-}
ref_name=${GITHUB_REF_NAME:-}
status=${INPUT_STATUS:-}

event_json=$(cat "${GITHUB_EVENT_PATH:-/nonexistent}" 2>/dev/null || echo '{}')

# mrkdwn-escape text that came from a user (PR titles, commit messages, job names).
esc() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Query the event payload; $1 is a jq program.
ev() {
  printf '%s' "$event_json" | jq -r "$1"
}

emit() {
  local delim="ghadelimiter_$RANDOM$RANDOM$RANDOM"
  printf '%s<<%s\n%s\n%s\n' "$1" "$delim" "$2" "$delim" >>"$out"
}

case "$event_name" in
pull_request | pull_request_target)
  number=$(ev '.pull_request.number // .number // empty')
  pr_title=$(ev '.pull_request.title // ""')
  url=$(ev '.pull_request.html_url // empty')
  origin="PR #$number"
  trigger="<${url:-$repo_url/pull/$number}|#$number: $(esc "$pr_title")>"
  ;;
push)
  message=$(ev '(.head_commit.message // "") | split("\n")[0]')
  url=$(ev '.head_commit.url // empty')
  origin="$ref_name @ $short_sha"
  trigger="<${url:-$repo_url/commit/$sha}|$(esc "${message:-$short_sha}")>"
  ;;
release)
  tag=$(ev '.release.tag_name // empty')
  name=$(ev '.release.name // empty')
  url=$(ev '.release.html_url // empty')
  origin=${tag:-$ref_name}
  trigger="<${url:-$repo_url/releases/tag/$origin}|$(esc "${name:-$origin}")>"
  ;;
workflow_dispatch)
  origin="$ref_name ($event_name)"
  trigger="$event_name by $(esc "${GITHUB_ACTOR:-unknown}")"
  ;;
*)
  origin="$ref_name ($event_name)"
  trigger=$event_name
  ;;
esac

# Failed jobs, labelled by their first matrix value when the name has one:
# "build (Stroma, aarch64-darwin, macos-latest)" becomes "Stroma".
failed=''
if [[ ${INPUT_FAILED_JOBS:-false} == true ]]; then
  if jobs_json=$(
    GH_TOKEN=${INPUT_GITHUB_TOKEN:-${GH_TOKEN:-}} gh api --paginate \
      "repos/$repo/actions/runs/${GITHUB_RUN_ID:-0}/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100" 2>/dev/null
  ); then
    failed=$(
      printf '%s' "$jobs_json" | jq -rs '
        [.[].jobs[] | select(.conclusion == "failure") | .name
          | sub("^[^(]+\\((?<m>[^,)]+)[^)]*\\)$"; "\(.m)")]
        | join(", ")'
    )
  else
    echo "::warning title=slack-notify::Could not list the run's jobs; grant actions: read to name the failed ones"
  fi
  failed=${failed:-unknown}
fi

if [[ -n ${INPUT_TITLE:-} ]]; then
  title=$INPUT_TITLE
else
  prefix=${INPUT_TITLE_PREFIX:-}
  if [[ -z $prefix ]]; then
    case "$status" in
    success) verb=succeeded ;;
    failure) verb=failed ;;
    cancelled) verb=cancelled ;;
    *) verb='' ;;
    esac
    prefix="${GITHUB_WORKFLOW:-Workflow}${verb:+ $verb}"
  fi
  title=$prefix
  if [[ -n $failed ]]; then
    title+=" for $failed"
  fi
  title+=" ($origin)"
fi

# $'\n' is assigned to a variable first: bash 3.2 (macOS) doesn't expand it
# inside a double-quoted ${var:+...}.
nl=$'\n'
fields=''
if [[ -n $failed ]]; then
  fields="Failed: $(esc "$failed")${nl}Trigger: $trigger"
fi
if [[ -n ${INPUT_FIELDS:-} ]]; then
  fields+="${fields:+$nl}$INPUT_FIELDS"
fi

context="<$repo_url|$repo> · <$repo_url/commit/$sha|$short_sha> · <$repo_url/actions/runs/${GITHUB_RUN_ID:-0}|View run>"

emit NOTIFY_STATUS "$status"
emit NOTIFY_TITLE "$title"
emit NOTIFY_FIELDS "$fields"
emit NOTIFY_CONTEXT "$context"
