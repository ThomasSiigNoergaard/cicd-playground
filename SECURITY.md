# Security policy

This is a personal learning repository. It is not a production service, but
security reports are still welcome and appreciated.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub private vulnerability reporting instead:
[Report a vulnerability](https://github.com/ThomasSiigNoergaard/cicd-playground/security/advisories/new)
(Security tab -> Advisories -> "Report a vulnerability").

Include what you found, how to reproduce it and the potential impact. You can
expect an acknowledgement within a week.

## Supported versions

Only the latest commit on `main` is supported.

## Security tooling in this repo

| Control | Where |
| --- | --- |
| Static analysis (C# and workflows) | CodeQL, `.github/workflows/codeql.yml` |
| Vulnerable dependency gate on PRs | `.github/workflows/dependency-review.yml` |
| Container image and IaC scanning | Trivy in `ci.yml` and `terraform.yml` |
| Repo security posture | OpenSSF Scorecard, `.github/workflows/scorecard.yml` |
| Automated dependency updates | `.github/dependabot.yml` |
| Build provenance and SBOM attestations | `.github/workflows/deploy.yml`, see `docs/supply-chain.md` |
| Keyless cloud access (no stored AWS keys) | GitHub OIDC, see `docs/oidc.md` |
| Secret scanning and push protection | Repository settings |
