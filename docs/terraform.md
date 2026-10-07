# Terraform layout and decisions

```
terraform/
  .tflint.hcl              shared tflint config (terraform + aws rulesets)
  bootstrap/               run ONCE locally with admin credentials (local state)
  modules/app/             the whole application stack, reused by every env
  environments/
    dev/                   thin root: backend + module "app" + dev settings
    prod/                  thin root: backend + module "app" + prod settings
```

## Why separate environment roots (and not workspaces or one root with tfvars)

| Option | Verdict |
|---|---|
| **Separate thin roots per env** (chosen) | Each env has its own state key, its own lock, its own plan, its own OIDC role and its own lock file. A mistake in dev cannot touch prod state. Differences between envs are explicit, reviewable code in `main.tf`, not hidden in a var file. |
| One root + `dev.tfvars` / `prod.tfvars` | Less duplication, but every plan has to remember `-var-file` and `-backend-config` together, and it is easy to apply prod vars against dev state. Env-specific *structure* (for example an extra resource only in prod) gets awkward. |
| Terraform CLI workspaces | Same code and backend with a `terraform.workspace` switch. Easy to apply to the wrong workspace, harder to give each env a different IAM role. HashiCorp itself recommends against CLI workspaces for separating environments with different credentials. |

All logic lives in `modules/app`. The roots are about 20 lines each, so the duplication cost is small, and the isolation benefit is large.

## Bootstrap (chicken-and-egg)

The S3 state bucket and the OIDC roles must exist before CI can run Terraform. `terraform/bootstrap` creates them using **local state** (gitignored). It is applied by a human with admin credentials, once per AWS account. See [terraform/bootstrap/README.md](../terraform/bootstrap/README.md).

- **State bucket:**
  - Versioning, so you can roll back a broken state file.
  - SSE encryption.
  - Public access block and `BucketOwnerEnforced` ownership.
  - A bucket policy that denies non-TLS access.
  - `prevent_destroy`.
- **Locking:** native S3 locking (`use_lockfile = true`, Terraform >= 1.10). Terraform writes a `<key>.tflock` object with a conditional `If-None-Match` PUT. DynamoDB is no longer needed, and the DynamoDB-based locking is deprecated.
- **Bootstrap state:** losing the local bootstrap state is not fatal. Everything can be re-imported with `terraform import`. You can also migrate it into the bucket afterwards by adding a backend block and running `terraform init -migrate-state`.

## Backend configuration

The env roots use a **partial backend**: the bucket name is not in git. CI passes it in from `vars.TF_STATE_BUCKET`:

```bash
terraform -chdir=terraform/environments/dev init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="region=eu-north-1"
```

The state key (`env/<env>/terraform.tfstate`) is hard-coded in each root, so dev and prod can never share a state file.

## Cost-conscious networking default

| Setting | Monthly cost (eu-north-1, approx.) | Notes |
|---|---|---|
| `use_private_subnets = false` (default) | 0 USD extra | Tasks run in public subnets with `assign_public_ip`. Their security group only accepts traffic **from the ALB security group**, so they are not reachable from the internet. Outbound traffic (ECR pulls, CloudWatch) goes straight through the internet gateway. |
| `use_private_subnets = true` | about 35 USD + data per env | Tasks run in private subnets behind **one** NAT gateway (not one per AZ). This is more realistic, and it is where you would add VPC endpoints for ECR, S3 and logs in production. |

Both envs use the cheap default. Flip the variable in `environments/prod/main.tf` to practise the private setup.

Other fixed costs to know about:

- **ALB:** about 18 USD/month per env, plus LCUs.
- **Fargate:** 0.25 vCPU / 0.5 GB is about 9 USD/month per running task.
- **Container Insights:** prod only, billed as CloudWatch custom metrics.
- **CloudWatch logs:** ingestion and storage.

ECR storage is cents.

## Who owns what: Terraform vs the deploy workflow

The ECS service is created with `desired_count = 0` and a placeholder task definition. It has `lifecycle { ignore_changes = [task_definition, desired_count] }`:

- **Terraform** owns the infrastructure: VPC, ALB, cluster, service shell, roles and log group.
- **The deploy workflow** owns the running image and the scale. It renders a new task definition revision with the image digest and sets the desired count to 1.

Without `ignore_changes`, every `terraform apply` would roll the service back to the placeholder image.

## Lock files (`.terraform.lock.hcl`)

The lock file records the exact provider versions and their checksums. Like `package-lock.json`, it keeps CI and laptops on identical providers, and protects against a tampered provider binary.

- **Root modules** (`bootstrap`, `environments/*`): the lock file **is committed**.
- **Shared modules** (`modules/*`): the lock file is **gitignored**. Only root modules use one, and versions are constrained in `versions.tf`.
- **Multi-platform hashes.** A lock file generated on Windows only contains Windows hashes, so CI (linux_amd64) would fail with checksum errors. After changing a provider version, regenerate the hashes for every platform:

  ```bash
  terraform -chdir=terraform/environments/dev providers lock \
    -platform=linux_amd64 -platform=windows_amd64 \
    -platform=darwin_amd64 -platform=darwin_arm64
  ```

- **Dependabot** (the `terraform` ecosystem) proposes provider bumps for each root and updates the lock files.

## Version pinning

- `required_version = ">= 1.10"` is needed for native S3 locking. CI pins the exact CLI version (`TF_VERSION` in `terraform.yml` and `_terraform-apply.yml`).
- `hashicorp/aws ~> 6.0` allows minor and patch updates but blocks the next major version, which may contain breaking changes.

## Linting and scanning

- `terraform fmt -check -recursive` checks formatting.
- `terraform validate` runs per stack, after `init -backend=false`, so no credentials are needed.
- **tflint** uses `terraform/.tflint.hcl`. It runs the recommended Terraform rules plus the AWS ruleset (invalid instance types, regions and so on), and requires every variable and output to be documented.
- **Trivy config scan** finds misconfigurations (for example an unencrypted bucket or an open security group) and uploads them as SARIF to the Security tab. Intentional exceptions are marked inline with `#trivy:ignore:<ID>` and a justification comment.

Run all offline checks locally:

```powershell
./scripts/terraform-check.ps1     # Windows / PowerShell
```

```bash
./scripts/terraform-check.sh      # Linux / macOS
```

## PR plans and applies

- **Pull requests:** `terraform.yml` plans **dev and prod** with the read-only plan role. Each environment gets one PR comment. New pushes **update** that comment instead of adding another one; the workflow finds it by a hidden `<!-- terraform-plan:<env> -->` marker.
  - Plans take the state lock (`-lock-timeout=2m`), so a plan never reads half-written state during an apply. That is why the plan role is allowed to write and delete `*.tflock` objects, but nothing else in the bucket.
- **Push to main:** apply dev, then apply prod (`_terraform-apply.yml`). Prod waits for a required reviewer on the `prod` environment.
  - Each apply job runs a fresh `plan -out=tfplan` and then applies exactly that file. The PR plan is not reused, because main may have moved since the PR was planned.
  - Running a workflow does not cancel an apply that is already in progress. Killing an apply mid-way can leave a stale lock and half-applied state.
