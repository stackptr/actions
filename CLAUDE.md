# CLAUDE.md

Shared composite GitHub Actions and reusable workflows for stackptr repos. The repo is public and other repos pin it by commit SHA, so keep every change small and every action's inputs stable.

## Layout

- `slack-notify/`: posts to Slack as the Hypha bot with `chat.postMessage`.
  - `notify.sh`: generic sender. Env in, payload out, no GitHub assumptions. Packaged as `packages.<system>.slack-notify` for services on rc hosts.
  - `github-context.sh`: derives title, fields, context and failed jobs from `GITHUB_*` and `$GITHUB_EVENT_PATH`.
  - `action.yml`: runs `github-context.sh`, then `notify.sh`.
  - `test/`: `run.sh` and fixtures under `test/cases/<name>/` (`env`, optional `event.json` and `jobs.json`, `expected.json`).
- `flake.nix`: the package, checks (shellcheck, payload fixtures) and formatter (alejandra).
- `.github/workflows/`: `ci.yml` (flake check, plus the action run in dry-run mode), `smoke.yml` (posts a real message), `approve-prs.yml` (approves my PRs here through the reusable workflow), `release.yml` (publishes a release for each version tag), and the reusable `approve.yml` (`workflow_call` only; approves the owner's PRs as teleoid from the caller's `approve` environment) and `update-flake.yml` (`workflow_call` only; updates the caller's `flake.lock` as teleotrope from its `update` environment, then merges once the required checks pass). A reusable workflow runs with the caller's event, repository and environments: a job reads environment secrets by declaring `environment:` itself, but they're empty unless the caller also sets `secrets: inherit` (`vars` arrive without it).

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

In a sandboxed cloud session `github:` inputs fail with HTTP 403 but `git clone` works: run `scripts/check-sandboxed` (and `scripts/check-sandboxed fmt .`) instead, which override nixpkgs with a shallow git fetch of the locked rev. Flake files must be `git add`ed first, or Nix can't see them.

## Secrets

This repo is under stackptr/ops's baseline: no repository-level secrets (ops's daily check fails if one appears), only main-only environments that ops manages. `SLACK_BOT_TOKEN` (Hypha's `xoxb-` token) is in `notify`, which `smoke.yml` declares; `approve` holds teleoid's key for `approve-prs.yml`. The owner seals secrets in ops and sets the Slack app's scopes; sessions can't, and shouldn't work around that.

`approve-prs.yml` calls this repo's own reusable `approve.yml` by local path (`./.github/workflows/approve.yml`). Under `pull_request_target` that resolves from `main`, so a PR's changes to `approve.yml` take effect here only once merged, while other repos keep the SHA they pin.

## Branching

- Trunk-based: short-lived branches off `main`, merged often. Name them `type-short-slug`, where `type` is `feat`, `fix`, `chore` or `refactor` and the slug is 2 to 4 words (e.g. `fix-thread-broadcast`). There is no host scope here.
- Cloud sessions assign a `claude/<words>-<id>` branch; name the branch by these rules instead.
- PR title: `type: short description`. PRs are squash-merged, so the title becomes the commit message.
- PR description: what changed, and what to test or verify.

## Guardrails

- Don't merge a PR, create or move a tag, or run `smoke.yml` unless asked. Only the admin role can push tags here anyway (stackptr/ops's "Release tags" ruleset), and a tag is what callers' Dependabot updates them to.
- Don't put private information in this repo: it is public.
- Don't change an input's name or default in a pinned release; add a new input instead.

## Releasing

Callers pin a release's commit SHA with its version as a comment (`@<sha> # v1.1.0`), and their Dependabot opens a PR for each newer release. A merge to `main` reaches no one until it's released.

- Version by what callers see: **patch** for fixes and docs-only changes callers might want, **minor** for a new action, workflow, input or output, **major** for a removed or renamed input or output, a changed default, or behavior a caller would have to adapt to. Docs-only changes don't need a release.
- To release: on an up-to-date `main`, `git tag -s vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`. `release.yml` checks the tag is on `main` and publishes the release with generated notes from the merged PRs.
- No floating major tag (`v1`): every caller pins a SHA, and a moving tag would need force-pushes.
- A PR that callers will need released says so in its description and proposes the version.

## Committing

- My git config requires signing, which you can't do (it needs an interactive GPG unlock). For commands that create commits, use `git -c commit.gpgsign=false …`, and never change git config to disable signing. Add a `Co-Authored-By:` trailer identifying yourself.

## Updating this file

- When a working solution reached through trial and error would help future sessions in this repo, add it to this file in the PR you're preparing and call it out in the PR description.

## Code style

- All files end with a newline.
- Run `nix fmt` after large changes; CI fails if it changes anything.
