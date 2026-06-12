# Security Policy

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

If you discover a security vulnerability in any FlowMatrix-AI repository, please report it privately using one of the following methods:

1. **GitHub Private Vulnerability Reporting** (preferred) — click the "Report a vulnerability" button on the repository's **Security** tab. This creates a private advisory visible only to maintainers.
2. **Email** — send details to [security@flowmatrixai.com](mailto:security@flowmatrixai.com).

### What to Include

- Description of the vulnerability
- Steps to reproduce (if applicable)
- Affected repository and version/branch
- Any potential impact you've identified

### Response Timeline

We will acknowledge your report within **5 business days** and aim to provide a resolution or mitigation plan promptly after triage.

## Scope

This policy applies to all repositories in the FlowMatrix-AI organization. Individual repositories may have their own `SECURITY.md` that supersedes this one.

## Secret Management

Secrets (API keys, tokens, credentials) must never be committed to git.

### Required practices

- **Never commit `.env` files.** Every repo ignores `.env` / `.env.*` via `.gitignore`; commit a sanitized `.env.example` instead.
- **Use a secrets manager** (AWS Secrets Manager / GitHub Actions secrets) for runtime credentials — not source files, docs, or planning notes.
- **Rotate immediately on exposure.** Purging git history does **not** invalidate a leaked secret; rotate the credential first, then scrub history.

### Tooling

- **Gitleaks CI** — add the "Gitleaks secret scan" workflow from *Actions → New workflow → By FlowMatrix-AI* (`workflow-templates/gitleaks.yml`). Runs on push/PR plus a weekly full-history sweep.
- **Pre-commit** — copy the shared [`.pre-commit-config.yaml`](.pre-commit-config.yaml) into a repo and run `pre-commit install` to block secrets before they are committed.

### Org-level controls (admins)

- Enable **Secret Scanning** and **Push Protection** org-wide (*Settings → Code security*). Push Protection blocks pushes containing recognized secrets — the highest-leverage preventive control.

### Responding to a committed secret

1. **Rotate / revoke** the credential at its provider.
2. **Purge history** with `git filter-repo --replace-text`, then force-push.
3. **Re-clone** all working copies (history rewrite changes every commit SHA).
4. If needed, ask GitHub Support to expire cached views of the old commits.
