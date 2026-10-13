# Supply chain security

This repo applies several overlapping layers. Each one answers a different question.

| Question | Control | Where |
|---|---|---|
| Can a compromised or retagged action run in my pipeline? | Actions are pinned to full commit SHAs | every workflow |
| Are my dependencies (NuGet, actions, Docker base image, Terraform providers) out of date? | Dependabot version updates, grouped weekly | `.github/dependabot.yml` |
| Does this PR add a vulnerable or badly-licensed dependency? | Dependency review | `dependency-review.yml` |
| Does my code have vulnerabilities? | CodeQL (C# and Actions) | `codeql.yml` |
| Does my container image ship known CVEs? | Trivy image scan | `ci.yml` |
| Is my infrastructure misconfigured? | Trivy config scan | `terraform.yml` |
| Did I commit a secret? | Secret scanning, push protection, and Copilot generic secret detection | repo settings |
| How healthy are my security practices overall? | OpenSSF Scorecard | `scorecard.yml` |
| Is the image running in prod the one CI built from this commit? | Build provenance attestation | `deploy.yml` |
| What is inside that image? | SBOM attestation | `deploy.yml` |

All scanners upload **SARIF** to code scanning, so every finding lands in one place: **Security > Code scanning**. Findings are deduplicated by tool (`category`), and PRs get inline annotations.

## SHA pinning

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

- **Why pin to a SHA?** A tag like `v4` is mutable. Whoever controls the action repo (or an attacker who compromises it, as in the `tj-actions/changed-files` incident in 2025) can move the tag to malicious code. A commit SHA is immutable.
- **Why the comment?** The trailing `# v7.0.1` comment keeps it readable. Dependabot understands it, and updates both the SHA and the comment in its PRs.
- **Resolving a SHA:** look up the SHA for a tag yourself with:

  ```bash
  gh api repos/actions/checkout/git/ref/tags/v7.0.1 --jq .object.sha
  # If .object.type is "tag" (an annotated tag), dereference it:
  gh api repos/actions/checkout/git/tags/<sha> --jq .object.sha
  ```

- **Enforcing pinning:** you can make it a rule under **Settings > Actions > General > "Require actions to be pinned to a full-length commit SHA"**.

## Least-privilege `GITHUB_TOKEN`

Every workflow starts with `permissions: {}` (no permissions at all). Each job then requests only what it needs, for example:

- `security-events: write` to upload SARIF.
- `id-token: write` to get an OIDC token (AWS, attestations).
- `attestations: write` to store attestations.
- `pull-requests: write` to post the plan comment.

A compromised step can therefore do very little with the token. Scorecard's `Token-Permissions` check verifies this.

## zizmor: static analysis for workflows

[zizmor](https://docs.zizmor.sh) is a linter for the *security* of GitHub Actions workflows. actionlint checks whether a workflow is valid; zizmor checks whether it is safe. `zizmor.yml` runs it on every PR and push that touches `.github/`, and uploads the findings to code scanning. Typical findings:

- **template-injection**: `${{ github.event.issue.title }}` (or any attacker-controllable value) pasted straight into a `run:` script, which lets a crafted title execute shell commands. The fix is to pass the value through `env:` and reference `"$VAR"`.
- **excessive-permissions**: a workflow without a top-level `permissions:` block, or with broad write scopes.
- **unpinned-uses**: actions referenced by tag instead of SHA.
- **artipacked**: `actions/checkout` leaving the token in `.git/config` (`persist-credentials: false` fixes it).
- **dangerous-triggers**: `pull_request_target` or `workflow_run` combined with checking out untrusted code.
- **cache-poisoning**: release workflows that restore caches a PR could have written.

Configuration lives in `.github/zizmor.yml`. One rule is disabled there: `self-repository` recommends the newer `uses: $/path` syntax over `uses: ./path`. The newer syntax is safer because it cannot pick up an action that an earlier step wrote into the workspace. actionlint does not understand it yet, though, so adopting it would break the lint job. The comment in the config says when to revisit this. The gh-aw generated `.lock.yml` files are scanned too; the gh-aw compiler hardens them.

Run it locally with [uv](https://docs.astral.sh/uv/):

```bash
uvx zizmor --offline --config .github/zizmor.yml .
```

## Dependabot

`.github/dependabot.yml` covers:

- **nuget**, via the solution root and central package management.
- **docker**, for the base images in the `Dockerfile`.
- **github-actions**, including the composite actions under `.github/actions/*`.
- **terraform**, for each root and the shared module: `bootstrap`, `modules/app`, `environments/dev` and `environments/prod`.

Updates are **grouped**, so you get one PR per ecosystem per week instead of twenty. A 7-day **cooldown** delays version updates until a release has been public for a week, so a compromised release that is pulled quickly never reaches this repo. Security updates (from **Dependabot alerts**) are separate, ignore the cooldown, and arrive as soon as an advisory is published. Commit messages use the `build(deps)` prefix, which passes the PR title lint and does not cut a release.

## Dependency review

`dependency-review.yml` diffs the dependency graph between the PR base and head:

- It **fails the PR on high or critical** advisories.
- It always posts a summary comment (`comment-summary-in-pr: always`).

Make it a required status check in a branch ruleset so it actually blocks merges.

## OpenSSF Scorecard

`scorecard.yml` runs weekly and on push to main. It grades the repo on about 18 checks: branch protection, pinned dependencies, token permissions, signed releases, SAST, fuzzing and so on.

- Results go to code scanning (SARIF).
- Results are also published to the public Scorecard API, which powers the README badge.
- Some checks (for example `Branch-Protection`) need a fine-grained PAT to read classic protection rules; the workflow runs without one. A lower score on that check in this lab is expected and not a real finding.
- A low score in a lab repo is expected. Read the remediation text for each check in the Security tab.

## Container image: build once, promote by digest

```
push to main
  -> build image once            (docker/build-push-action, provenance/SBOM disabled on the build itself)
  -> push to dev ECR as :<git-sha> (immutable tags, scan on push)
  -> attest provenance + SBOM    (bound to sha256 digest)
  -> deploy dev, smoke test
  -> [prod approval]
  -> copy SAME digest to prod ECR (docker buildx imagetools create, verified)
  -> deploy prod by digest
```

- **The task definition references `repo@sha256:...`, not a tag.** Prod therefore runs byte-for-byte what was tested in dev, and nothing can retag underneath it.
- **ECR tags are `IMMUTABLE`.** Re-pushing `:<sha>` with different content is rejected.
- **ECR uses basic scan on push.** Results are visible in the ECR console. The CI Trivy scan already gates PRs earlier.

## Attestations (provenance and SBOM)

An **attestation** is a signed, verifiable statement about an artifact. GitHub signs it with a short-lived Sigstore certificate bound to the workflow's OIDC identity, so no signing keys need to be managed. Attestations are stored in GitHub's attestation API, and, with `push-to-registry: true`, also next to the image in ECR as OCI referrers.

- **Build provenance:** `actions/attest-build-provenance` uses the SLSA provenance predicate. It records which repo, workflow, commit and runner produced which digest.
- **SBOM:** `anchore/sbom-action` (Syft) generates an SPDX JSON SBOM from the pushed image, and `actions/attest-sbom` signs it against the same digest.

### Verify

You need the `gh` CLI (2.49+) and a registry login if you pull the image. Attestations are keyed by **digest**, so verifying the prod copy also works, because the digest is identical.

```bash
REGION=eu-north-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/cicd-playground-dev
DIGEST=$(aws ecr describe-images --repository-name cicd-playground-dev \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageDigest' --output text)

# gh pulls the image manifest, so log in to ECR first
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# 1. Provenance (default predicate type is SLSA provenance v1)
gh attestation verify oci://$REPO@$DIGEST -R ThomasSiigNoergaard/cicd-playground

# 2. SBOM
gh attestation verify oci://$REPO@$DIGEST -R ThomasSiigNoergaard/cicd-playground \
  --predicate-type https://spdx.dev/Document/v2.3

# Stricter: only accept images built by the deploy workflow on main
gh attestation verify oci://$REPO@$DIGEST -R ThomasSiigNoergaard/cicd-playground \
  --signer-workflow ThomasSiigNoergaard/cicd-playground/.github/workflows/deploy.yml \
  --source-ref refs/heads/main

# Print the SBOM itself
gh attestation verify oci://$REPO@$DIGEST -R ThomasSiigNoergaard/cicd-playground \
  --predicate-type https://spdx.dev/Document/v2.3 --format json \
  --jq '.[0].verificationResult.statement.predicate.packages[].name'
```

You can also browse the attestations in the GitHub UI under **Actions > Attestations**.

### Going further

- **Enforce at deploy time.** Verify the attestation in the deploy job before `amazon-ecs-deploy-task-definition`, or use a Kubernetes admission controller (Sigstore policy-controller, Kyverno) on other platforms.
- **Immutable releases.** Tag releases and attest release artifacts the same way.
- **Base image pinning.** The `Dockerfile` already references base images by tag *and* digest, written literally in the `FROM` lines so Dependabot can parse and update both.
