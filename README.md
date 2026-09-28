# .github

Organization-level defaults for the FlowMatrix-AI GitHub org.

- `profile/README.md` — public org profile (shown on github.com/FlowMatrix-AI)
- `SECURITY.md` — vulnerability reporting guidance (applies to all repos without their own)
- `PULL_REQUEST_TEMPLATE.md` — default PR template (applies to all repos without their own)
- `ISSUE_TEMPLATE/` — default issue forms (applies to all repos without their own)

## This repository must stay public

Making it private breaks three things, and the third is the least visible:

| Depends on this repo being public | What breaks if it goes private |
|---|---|
| The org profile (`profile/README.md`) | the profile goes dark; GitHub requires a public `.github` |
| The default community health files (`ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md`, `SECURITY.md`) | they stop applying org-wide ("a repository for default files cannot be private") |
| The unauthenticated fetch of `.gitleaks.toml` in `.github/workflows/gitleaks.yml` | the required `gitleaks / gitleaks` check fails in every calling repo: `raw.githubusercontent.com` returns 404 for a private repo |

## `.gitleaks.toml` is live everywhere the moment it merges

Callers pin `gitleaks.yml` by digest, but that pins the workflow code, not the
ruleset it runs with: the workflow fetches `.gitleaks.toml` from `main` on every
run. A change to it (an over-broad allowlist in particular) changes what every
repo detects on its next scan, and fails open: checks stay green. `CODEOWNERS`
names an owner for it and for the workflows.

The fetch is deliberately fail-closed (`curl -f`, no fallback), so a scan never
runs with an empty or different ruleset. The accepted cost: if
`raw.githubusercontent.com` is unreachable, the required check fails and no repo
in the org can merge until it is back.

A repo that needs its own `.gitleaks.toml` must `[extend] path =
".gitleaks.org.toml"`: a local config otherwise replaces the org ruleset
entirely, and the scan still shows green.
