# Copilot instructions for cicd-playground

This is a hands-on **learning repo** for modern CI/CD on GitHub. It deploys a .NET 9 minimal API to AWS ECS Fargate using Terraform and GitHub Actions with OIDC. Readability and teaching value matter: comment the *why* wherever something is non-obvious.

## Stack

- **App:** .NET 9 minimal API in `src/CicdPlayground.Api`. It uses built-in OpenAPI, ASP.NET health checks and JSON console logging.
- **Tests:** xUnit and `WebApplicationFactory` in `tests/CicdPlayground.Api.Tests`, with coverage via coverlet.
- **Build settings:**
  - `global.json` pins the SDK.
  - `Directory.Build.props` enables nullable, warnings as errors and analyzers.
  - `Directory.Packages.props` handles central package management. Add package versions there, never in `.csproj` files.
- **Container:** multi-stage `Dockerfile`. The runtime is chiseled, runs as non-root and listens on port 8080. Base images are pinned by tag and digest.
- **Infra:** Terraform >= 1.10 with AWS provider 6.x.
  - `terraform/bootstrap` is run once locally, with local state.
  - `terraform/modules/app` is the shared module.
  - `terraform/environments/{dev,prod}` are thin roots that use the S3 backend with `use_lockfile`.
- **CI/CD:** workflows live in `.github/workflows`. Files prefixed with `_` are reusable (`workflow_call`). Local composite actions live in `.github/actions`.

## Build, test, lint

```bash
dotnet restore
dotnet build --configuration Release
dotnet test --configuration Release
docker build -t cicd-playground:local .
./scripts/terraform-check.sh     # or scripts/terraform-check.ps1: fmt, validate, tflint for every stack
actionlint                       # lint workflows
```

## Rules (non-negotiable)

- **Never use the em dash character.** Use a plain dash `-`. This applies to code, docs and commit messages.
- **Pin every third-party GitHub Action to a full 40-character commit SHA**, with a trailing version comment:

  ```yaml
  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  ```

- **Least privilege for `GITHUB_TOKEN`:** set top-level `permissions: {}` and grant only what each job needs.
- **No long-lived cloud credentials.** AWS access is GitHub OIDC only, through `aws-actions/configure-aws-credentials` and role ARNs in repository or environment **variables**, not secrets.
- **AWS jobs must skip gracefully when AWS variables are unset.** Follow the existing `preflight` pattern, and write a notice to `$GITHUB_STEP_SUMMARY`.
- **Do not interpolate untrusted input into `run:` scripts.** This includes `${{ github.event.* }}`. Pass values through `env:` instead.
- **Promote images by digest, never rebuild per environment.**
- Use conventional commits, for example `feat:`, `fix:`, `docs:`, `ci:`, `chore:` and `deps:`.
- Keep the README walkthrough and `docs/` in sync when behaviour changes.
