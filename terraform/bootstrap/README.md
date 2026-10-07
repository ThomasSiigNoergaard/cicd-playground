# terraform/bootstrap

One-time stack, run **locally with administrator credentials**. It creates:

| Resource | Why |
|---|---|
| S3 bucket `<project>-tfstate-<account>-<region>` | Remote state for the environment stacks. It has versioning, SSE, a public access block, BucketOwnerEnforced and a TLS-only bucket policy. Locking uses native S3 lock files (`use_lockfile = true`), so there is no DynamoDB table. |
| IAM OIDC provider `token.actions.githubusercontent.com` | Lets AWS STS trust tokens issued by GitHub Actions. |
| Role `<project>-github-plan` | Assumable only by `pull_request` jobs in this repo. It is read-only, plus it can manage the state lock file. |
| Roles `<project>-github-deploy-dev` and `-prod` | Assumable only by jobs running in the matching GitHub environment. Used for `terraform apply` and app deploys. |

## Run it

```bash
cd terraform/bootstrap
aws sts get-caller-identity          # confirm you are in the right account
terraform init
terraform apply
terraform output -raw gh_variable_commands   # paste the printed commands
```

If the account already has the GitHub OIDC provider, run this instead: `terraform apply -var create_oidc_provider=false`.

## Where does this stack keep its own state?

Locally, in `terraform.tfstate`. That file is git-ignored on purpose. Keep it somewhere safe, for example a password manager attachment. If you prefer, migrate it into the bucket it just created. Add the block below and run `terraform init -migrate-state`:

```hcl
terraform {
  backend "s3" {
    bucket       = "<state_bucket_name output>"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
```

The lab keeps it local, so the bootstrap is easy to destroy at the end. See README step 10.
