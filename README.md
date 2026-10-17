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

## `.gitleaks.toml` resolves at the ref the caller pinned

A caller pins `gitleaks.yml@<digest>`, and that digest now covers the ruleset as
well as the workflow code: the workflow fetches `.gitleaks.toml` at
`job.workflow_sha` — the commit of the reusable workflow file being run — rather
than from `main`.

It did not always. The pin used to freeze the detector (`gitleaks-version` is an
input default in the workflow file) while the rules it ran with were re-fetched
from `main` on every run, so merging an over-broad allowlist here shrank
detection in every calling repo on its next scan, with no commit, no PR and no
review anywhere else, and every required check stayed green. That failed open,
which is the one direction a scanner must not fail. A weakening of detection is
now a change to a ref the consuming repo controls.

A caller on `@main`, or any branch, is unaffected: `job.workflow_sha` resolves to
that branch's current head. The cost falls on pinned callers — a fix to the
shared ruleset reaches them only when the pin moves, which is Renovate's digest
PR. A repo on a stale pin scans with a stale ruleset instead of with a stale
binary running current rules, and that is the more honest of the two.

Each run records the ruleset commit and its `sha256` in the job summary, so what
a scan actually ran with is legible from the run.

`CODEOWNERS` names an owner for `.gitleaks.toml` and for the workflows.

The fetch is deliberately fail-closed (`curl -f`, no fallback, and an empty
`job.workflow_sha` aborts the step), so a scan never runs with an empty,
different or unknown ruleset. The accepted cost: if `raw.githubusercontent.com`
is unreachable, the required check fails and no repo in the org can merge until
it is back.

A repo that needs its own `.gitleaks.toml` must `[extend] path =
".gitleaks.org.toml"`: a local config otherwise replaces the org ruleset
entirely, and the scan still shows green.
