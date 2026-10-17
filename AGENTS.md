# AGENTS.md

## Policy

Org engineering policy is authoritative and lives in
**[`FlowMatrix-AI/eng-governance`](https://github.com/FlowMatrix-AI/eng-governance)**.
Read it rather than inferring the rules from surrounding code:

| Where | What |
| --- | --- |
| [`DECISIONS.md`](https://github.com/FlowMatrix-AI/eng-governance/blob/main/DECISIONS.md) | Ratified engineering decisions, with the date each was locked |
| [`standards/`](https://github.com/FlowMatrix-AI/eng-governance/tree/main/standards) | Language, testing, security, dependencies, documentation |
| [`process/`](https://github.com/FlowMatrix-AI/eng-governance/tree/main/process) | Ownership, code review, pull requests, releases, design reviews |
| [`principles/`](https://github.com/FlowMatrix-AI/eng-governance/tree/main/principles) | Architecture and engineering principles |

Anything this file does not state follows those. What it *does* state
**overrides** org defaults for this repo — so say it here, rather than
restating policy that already lives there and will drift from it.

Cross-cutting technical documentation with no owning repo lives in
[`technical-docs`](https://github.com/FlowMatrix-AI/technical-docs).

## Project

Organization-level defaults for the `FlowMatrix-AI` GitHub org, and the org's
shared secret-scanning plant. It holds two reusable workflows
(`gitleaks.yml`, `commit-email.yml`), the org gitleaks ruleset
(`.gitleaks.toml`), the Actions workflow-template entry that seeds new repos,
the shared `.pre-commit-config.yaml`, and the community health files
(`SECURITY.md`, `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/`) plus
`profile/README.md`. **Every active repo in the org but this one calls
`gitleaks.yml`** from its own `.github/workflows/secret-scan.yml` — 69 of 70,
this repo being the exception because it calls it through a local ref — and the
resulting `gitleaks / gitleaks` status is a required check, so this repo gates
merges fleet-wide. `commit-email.yml` has no caller in the org today.

## Commands

```bash
# The only automated test here. CI does NOT run it — ci.yml is a bare `ok`.
# Needs python3 with PyYAML; extracts the workflow's own run: block and
# exercises it against throwaway git repos in a temp dir.
bash tests/commit-email.test.sh

# Run this repo's own scan (it calls gitleaks.yml through a local ref).
gh workflow run secret-scan.yml

# Who calls the reusable workflow right now.
gh api -X GET search/code -f per_page=100 \
  -f q='org:FlowMatrix-AI "FlowMatrix-AI/.github/.github/workflows/gitleaks.yml"' \
  --jq '.items[] | select(.path==".github/workflows/secret-scan.yml") | .repository.name' \
  | sort -u
```

## Architecture

| Path | What it is |
| --- | --- |
| `.github/workflows/gitleaks.yml` | Reusable (`workflow_call`). Installs the gitleaks **binary** (MIT, free) and scans. Input `gitleaks-version` defaults to a pinned release. |
| `.github/workflows/commit-email.yml` | Reusable. Checks only the commits a PR/push *adds* carry a `*@flowmatrixai.com` (or allowed bot) author **and** committer. For public repos. No caller yet. |
| `.github/workflows/secret-scan.yml` | This repo's own caller. Uses the local ref `./.github/workflows/gitleaks.yml` on purpose. |
| `.github/workflows/ci.yml` | Trivial always-pass `ok`, so branch protection stays uniform. |
| `.gitleaks.toml` | The org ruleset: `[extend] useDefault = true`, one shared `[allowlist]`, and extra `[[rules]]`. |
| `workflow-templates/` | The Actions "new workflow" template a repo adopts. References `@main`, not a digest. |
| `.pre-commit-config.yaml` | Copied into repos so the local gate runs the same gitleaks as CI. Renovate manages it via `:enablePreCommit`. |
| `profile/`, `SECURITY.md`, `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/` | Org defaults. They apply only because this repo is public. |
| `renovate.json` | Carries a `customManager` that tracks a version pinned as a `workflow_call` input `default:` annotated with `# renovate:`, plus a rule disabling updates to this repo's references to itself. |

`gitleaks-version` is visible to Renovate only because of the `# renovate:`
comment sitting directly above `default:` — the manager matches the pair.
Renovate's built-in `customManagers:githubActionsVersions` only matches keys
ending in `_VERSION`, so a workflow input default is invisible to it; that is
how the pin sat on 8.21.2 for a year.

## What NOT to do

- **Do not make this repo private.** Three things break, and the third is
  silent: the org profile goes dark, the default community health files stop
  applying org-wide, and the unauthenticated fetch of `.gitleaks.toml` 404s so
  the required `gitleaks / gitleaks` check fails in every caller.
- **Do not fetch `.gitleaks.toml` from `main`.** It is fetched at
  `job.workflow_sha`, the commit of the reusable workflow file being run, so a
  caller's digest pin covers the ruleset as well as the workflow code. Fetching
  from a branch instead made the pin half a pin, and the uncovered half failed
  **open**: merging a broadened allowlist here shrank detection in every calling
  repo on its next scan, with no commit or review anywhere else, while every
  required check stayed green. A caller on `@main` is unaffected either way.
  The cost of the pin is that a ruleset fix reaches a pinned repo only when its
  pin moves; a repo on a stale pin was already running a stale **binary**, so
  pinning makes the staleness visible in one place rather than half-hidden.
- **Still treat a ruleset edit as a fleet-wide security change.** The pin means
  a weakening lands repo by repo as pins move, not instantly — it does not mean
  it is reviewed. Code-owner review on `.gitleaks.toml` is not required by any
  ruleset yet (eng-governance #111).
- **Do not add a repo-local `.gitleaks.toml` without inheriting.** A local
  config *replaces* the org ruleset and the scan still shows green. Use
  `[extend] path = ".gitleaks.org.toml"`. Never set `useDefault` alongside
  `path`; gitleaks rejects the combination outright.
- **Do not add a fallback to the `curl -f` fetch.** Fail-closed is deliberate:
  a scan must never run with a different or empty ruleset. The accepted cost is
  that an unreachable `raw.githubusercontent.com` blocks merges org-wide.
- **Do not pin `workflow-templates/gitleaks.yml` to a digest**, and do not
  re-enable Renovate for `FlowMatrix-AI/.github` in this repo's
  `renovate.json`. The template is copied verbatim into *other* repos, so it
  cannot use a local `./` ref, and left managed Renovate chases this repo's own
  HEAD every week — 8 of the 11 commits before that rule were that self-chase,
  and each one reset `renovate/stability-days` on every downstream digest PR in
  the org, stranding five of them for 45–54 days.
- **Do not point `.github/workflows/secret-scan.yml` at the full
  `FlowMatrix-AI/.github/...` path.** The local `./` ref exists precisely so
  there is no self-digest to bump.
- **Do not switch to `gitleaks/gitleaks-action`.** It requires a paid
  `GITLEAKS_LICENSE` for organization repos. The binary is the whole point.
- **Do not bump `.pre-commit-config.yaml`'s `rev` and the workflow's
  `gitleaks-version` default separately.** They are the local gate and CI
  running the same detection rules; drift between them is invisible.
- **Do not assume CI covers `tests/commit-email.test.sh`.** `ci.yml` only
  echoes `ok`. Run the test by hand after touching `commit-email.yml`.
