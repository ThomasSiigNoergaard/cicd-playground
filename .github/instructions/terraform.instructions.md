---
applyTo: "terraform/**"
---

# Terraform conventions

- Terraform `>= 1.10` and AWS provider `~> 6.0`. Declare constraints in `versions.tf` of every root and module.
- **State:**
  - Use the S3 backend with native locking (`use_lockfile = true`). Do not use DynamoDB.
  - Backend config is partial: the bucket is passed via `-backend-config` at init.
- **Layout:**
  - Put shared logic in `terraform/modules/app`.
  - `environments/<env>` roots only wire variables and the backend. Do not duplicate resources there.
- **Tagging:** tag everything via the provider `default_tags`. Do not repeat common tags on every resource.
- **Naming:** use `"${var.project_name}-${var.environment}"` (`local.name`) as the base name.
- **Variables:** every variable needs a `description` and `type`. Add `validation` blocks where values are constrained.
- **Outputs:** give every output a `description`.
- **Security:**
  - Prefer least-privilege IAM.
  - When a scanner finding is intentionally accepted, suppress it inline with `#trivy:ignore:<ID>`, plus a comment explaining the trade-off.
- **Comments:** explain cost and security trade-offs. This is a learning repo.
- **Validation:** run `scripts/terraform-check.sh` (fmt, validate with `-backend=false`, tflint) before committing.
- **Lock files:**
  - Commit `.terraform.lock.hcl` for root stacks.
  - Do not commit it for `modules/`.
  - Generate lock files with `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64`.
