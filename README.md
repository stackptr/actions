# actions

Shared composite GitHub Actions for [stackptr](https://github.com/stackptr) repos.

## slack-notify

Posts a status message to Slack as the Hypha bot with `chat.postMessage`: one format for CI failures, releases and deploys.

```yaml
notify:
  needs: [lint, build]
  if: failure()
  runs-on: ubuntu-latest
  permissions:
    actions: read
  steps:
  - uses: stackptr/actions/slack-notify@<sha> # v1.0.0
    with:
      token: ${{ secrets.SLACK_BOT_TOKEN }}
      status: failure
      failed-jobs: true
```

Pin by commit SHA with a version comment; Dependabot bumps it. The preview for that call is `:x: CI failed for Stroma (PR #659)`, with Failed and Trigger fields and links to the repo, commit and run.

A success message from a release workflow, which shouldn't fail the release if Slack is down:

```yaml
  - uses: stackptr/actions/slack-notify@<sha> # v1.0.0
    continue-on-error: true
    with:
      token: ${{ secrets.SLACK_BOT_TOKEN }}
      status: success
      title: llm-profile ${{ steps.release.outputs.tag }} released
      fields: |
        Release: <${{ github.server_url }}/${{ github.repository }}/releases/tag/${{ steps.release.outputs.tag }}|${{ steps.release.outputs.tag }}>
```

### Inputs

| Input | Default | Notes |
|---|---|---|
| `token` | required | Bot token (`xoxb-…`) with `chat:write`, plus `chat:write.public` or an invite to each channel. Not needed with `dry-run`. |
| `status` | required | `success`, `failure`, `cancelled` or `info`. Pass it explicitly: `job.status` isn't available in input defaults. |
| `channel` | `#updates` | Name or ID. |
| `title` | derived | Headline and notification preview. Derived as `<title-prefix> for <failed jobs> (<origin>)`; the `for …` part appears only with `failed-jobs`. |
| `title-prefix` | workflow name + `succeeded`/`failed`/`cancelled` | `info` uses the workflow name alone. |
| `fields` | | One `Label: value` per line. The value is mrkdwn: escape `&`, `<` and `>` in untrusted text. |
| `failed-jobs` | `false` | `true` lists the run's failed jobs and adds **Failed** and **Trigger** fields. Needs `permissions: actions: read`. |
| `github-token` | `github.token` | Used only for listing jobs. |
| `thread-ts` | | Reply in this message's thread. |
| `broadcast` | `false` | With `thread-ts`, also show the reply in the channel. |
| `dry-run` | `false` | Build the payload, skip the Slack call. |

Outputs: `ts` and `channel` of the posted message (feed them to a later call's `thread-ts` and `channel`), and `payload` in dry-run mode.

### Message format

- `text` is `<emoji> <title>` and is both the notification preview and the headline: success `:white_check_mark:`, failure `:x:`, cancelled `:warning:`, info `:information_source:`.
- One attachment colored by status (`#2EB67D`, `#CC0000`, `#ECB22E`, `#439FE0`) with a section of fields (`*Label*` over the value) and a context line `repo · short sha · View run`. A message with no fields and no context is plain text.
- Link unfurling is off.

`origin` in the title is `PR #<n>` for pull requests, `<branch> @ <short sha>` for pushes, the tag for releases, and `<ref> (<event>)` otherwise. **Trigger** is the PR link, the head commit's first line, the release link, or the event. Labels in **Failed** use a job's first matrix value when its name has one (`build (Stroma, aarch64-darwin, macos-latest)` shows as `Stroma`), otherwise its name.

User text (PR titles, commit messages, job names) is escaped, and everything is built with `jq` from `$GITHUB_EVENT_PATH`, so a quote or backslash in a title can't break the payload.

### Outside Actions

`notify.sh` is the sender and knows nothing about GitHub; the flake packages it for services (a systemd unit, for example):

```bash
SLACK_TOKEN_FILE="$CREDENTIALS_DIRECTORY/slack-token" SLACK_CHANNEL='#alerts' \
  NOTIFY_STATUS=failure NOTIFY_TITLE='backup failed on glyph' \
  NOTIFY_FIELDS=$'Unit: restic.service\nExit: 1' \
  nix run github:stackptr/actions#slack-notify
```

The variables are documented at the top of [`slack-notify/notify.sh`](slack-notify/notify.sh).

## Development

`nix flake check` runs shellcheck, builds the package and diffs every fixture in `slack-notify/test/cases` against its expected dry-run payload. `smoke.yml` posts real messages when dispatched.
