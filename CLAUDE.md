# CLAUDE.md

Shared composite GitHub Actions for stackptr repos. The repo is public and other repos pin it by commit SHA, so keep every change small and every action's inputs stable.

## Layout

- `slack-notify/`: posts to Slack as the Hypha bot with `chat.postMessage`.
  - `notify.sh`: generic sender. Env in, payload out, no GitHub assumptions. Packaged as `packages.<system>.slack-notify` for services on rc hosts.
  - `github-context.sh`: derives title, fields, context and failed jobs from `GITHUB_*` and `$GITHUB_EVENT_PATH`.
  - `action.yml`: runs `github-context.sh`, then `notify.sh`.
  - `test/`: `run.sh` and fixtures under `test/cases/<name>/` (`env`, optional `event.json` and `jobs.json`, `expected.json`).
- `flake.nix`: the package, checks (shellcheck, payload fixtures) and formatter (alejandra).
- `.github/workflows/`: `ci.yml` (flake check, plus the action run in dry-run mode), `smoke.yml` (posts a real message).

## Writing actions

- Pass inputs to scripts through `env:`, never by interpolating `${{ inputs.* }}` or event data into `run:`.
- Build JSON with `jq --arg`, never by string concatenation, and read event data from `$GITHUB_EVENT_PATH`.
- Keep scripts portable to the macOS runner's bash: no `mapfile`, associative arrays or `${var,,}`.
- Third-party actions are pinned by commit SHA with a `# vX.Y.Z` comment; Dependabot bumps them.
- A fixture changes with the behavior it covers: `UPDATE=1 slack-notify/test/run.sh slack-notify` rewrites `expected.json`, then review the diff.

## Checking a change

```bash
nix-flake check            # shellcheck, package build, payload fixtures
nix fmt                    # alejandra
```

In a sandboxed cloud session `github:` inputs fail with HTTP 403 but `git clone` works: run `scripts/check-sandboxed` instead, which overrides nixpkgs with a shallow git fetch of the locked rev. Evaluate nothing else there; CI runs the full check.

## Secrets

`SLACK_BOT_TOKEN` (Hypha's `xoxb-` token) is a per-repo Actions secret: personal accounts have no account-level secrets. The owner adds it and the Slack app scopes; sessions can't, and shouldn't work around that.

## Branching

- Trunk-based: short-lived branches off `main`, merged often. Name them `type-short-slug`, where `type` is `feat`, `fix`, `chore` or `refactor` and the slug is 2 to 4 words (e.g. `fix-thread-broadcast`). There is no host scope here.
- Cloud sessions assign a `claude/<words>-<id>` branch; name the branch by these rules instead.
- PR title: `type: short description`. PRs are squash-merged, so the title becomes the commit message.
- PR description: what changed, and what to test or verify.

## Guardrails

- Don't merge a PR, create or move a tag, or run `smoke.yml` unless asked. Callers pin tags and SHAs, so moving `v1` changes every caller at once.
- Don't put private information in this repo: it is public.
- Don't change an input's name or default in a pinned release; add a new input instead.

## Committing

- My git config requires signing, which you can't do (it needs an interactive GPG unlock). For commands that create commits, use `git -c commit.gpgsign=false …`, and never change git config to disable signing. Add a `Co-Authored-By:` trailer identifying yourself.

## Updating this file

- When a working solution reached through trial and error would help future sessions in this repo, add it to this file in the PR you're preparing and call it out in the PR description.

## Code style

- All files end with a newline.
- Run `nix fmt` after large changes; CI fails if it changes anything.
