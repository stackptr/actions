#!/usr/bin/env bash
# Run the slack-notify fixtures: usage `run.sh <slack-notify dir>`.
#
# Each test/cases/<name>/ holds `env` (KEY=VALUE lines), an optional
# `event.json` ($GITHUB_EVENT_PATH) and `jobs.json` (what `gh api` returns),
# and `expected.json`, the dry-run payload. A case that sets GITHUB_EVENT_NAME
# runs github-context.sh first, like the action does. `UPDATE=1` rewrites
# expected.json; review the diff.
set -euo pipefail

self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

# Read a file the way the runner reads $GITHUB_ENV: NAME<<DELIM ... DELIM.
load_github_env() {
  local line name delim l value sep
  while IFS= read -r line; do
    name=${line%%<<*}
    delim=${line#*<<}
    value='' sep=''
    while IFS= read -r l && [[ $l != "$delim" ]]; do
      value+="$sep$l"
      sep=$'\n'
    done
    export "$name=$value"
  done <"$1"
}

# Runs in a clean environment (re-executed by run_case).
if [[ ${1:-} == --case ]]; then
  src=$2 dir=$3
  set -a
  # shellcheck disable=SC1091
  . "$dir/env"
  set +a
  if [[ -n ${GITHUB_EVENT_NAME:-} ]]; then
    export GITHUB_EVENT_PATH=$dir/event.json STUB_JOBS_JSON=$dir/jobs.json
    export GITHUB_ENV=$WORK/github_env
    : >"$GITHUB_ENV"
    bash "$src/github-context.sh"
    load_github_env "$GITHUB_ENV"
  fi
  SLACK_CHANNEL=${SLACK_CHANNEL:-#updates} NOTIFY_DRY_RUN=1 bash "$src/notify.sh"
  exit
fi

src=$(cd "$1" && pwd)
WORK=$(mktemp -d)
export WORK
trap 'rm -rf "$WORK"' EXIT
fail=0

mkdir "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/bin/sh
cat "$STUB_JOBS_JSON"
STUB
cat >"$WORK/bin/curl" <<'STUB'
#!/bin/sh
cat "$STUB_CURL_RESPONSE"
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

# The environment is cleared so a case sees only what its env file sets.
clean() {
  env -i PATH="$WORK/bin:$PATH" HOME="$WORK" WORK="$WORK" "$@"
}

for dir in "$src"/test/cases/*/; do
  name=$(basename "$dir")
  if ! actual=$(clean bash "$self" --case "$src" "${dir%/}" 2>"$WORK/stderr"); then
    echo "FAIL $name: exited non-zero"
    cat "$WORK/stderr"
    fail=1
    continue
  fi
  if [[ -n ${UPDATE:-} ]]; then
    jq -S . <<<"$actual" >"$dir/expected.json"
    echo "updated $name"
  elif diff <(jq -S . "$dir/expected.json") <(jq -S . <<<"$actual") >"$WORK/diff"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    cat "$WORK/diff"
    fail=1
  fi
done

# Response handling, with curl stubbed out.
send() {
  clean NOTIFY_STATUS=info NOTIFY_TITLE=hello SLACK_CHANNEL='#updates' \
    STUB_CURL_RESPONSE="$WORK/response" GITHUB_OUTPUT="$WORK/output" "$@" \
    bash "$src/notify.sh"
}
check() { # name, condition result
  if [[ $2 == 0 ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    fail=1
  fi
}

echo '{"ok":true,"ts":"1700000000.000100","channel":"C0123"}' >"$WORK/response"
: >"$WORK/output"
out=$(send SLACK_TOKEN=xoxb-secret)
check "send: prints ts and channel" "$([[ $out == $'ts=1700000000.000100\nchannel=C0123' ]] && echo 0 || echo 1)"
check "send: writes outputs" "$([[ $(cat "$WORK/output") == $'ts=1700000000.000100\nchannel=C0123' ]] && echo 0 || echo 1)"

printf 'xoxb-from-file\n' >"$WORK/token"
check "send: token file" "$(send SLACK_TOKEN_FILE="$WORK/token" >/dev/null 2>&1 && echo 0 || echo 1)"

echo '{"ok":false,"error":"channel_not_found","response_metadata":{"messages":["no such channel"]}}' >"$WORK/response"
err=$(send SLACK_TOKEN=xoxb-secret 2>&1 >/dev/null) && rc=0 || rc=$?
check "send: ok=false exits 1" "$([[ $rc == 1 ]] && echo 0 || echo 1)"
check "send: ok=false names the error" "$([[ $err == *channel_not_found* && $err == *"no such channel"* ]] && echo 0 || echo 1)"

echo '<html>bad gateway</html>' >"$WORK/response"
check "send: non-JSON response fails" "$(send SLACK_TOKEN=xoxb-secret >/dev/null 2>&1 && echo 1 || echo 0)"

check "send: empty token fails" "$(send SLACK_TOKEN= >/dev/null 2>&1 && echo 1 || echo 0)"
check "send: bad status fails" "$(send SLACK_TOKEN=x NOTIFY_STATUS=bogus >/dev/null 2>&1 && echo 1 || echo 0)"
check "send: malformed field fails" "$(send SLACK_TOKEN=x NOTIFY_FIELDS='no separator' >/dev/null 2>&1 && echo 1 || echo 0)"

out=$(send NOTIFY_DRY_RUN=1 SLACK_TOKEN=xoxb-secret)
check "dry-run: no token in output" "$([[ $out != *xoxb-secret* ]] && echo 0 || echo 1)"

exit "$fail"
