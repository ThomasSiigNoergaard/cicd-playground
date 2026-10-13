# -----------------------------------------------------------------------------
# tflint configuration shared by every Terraform stack in this repo.
# Run from a stack directory with:  tflint --config=$(git rev-parse --show-toplevel)/terraform/.tflint.hcl
# (the CI workflow and scripts/terraform-check.ps1 do this for you).
# -----------------------------------------------------------------------------
config {
  # Also lint the module code reached through `module` blocks.
  call_module_type = "local"
}

# Core Terraform language rules (unused declarations, naming, pinned versions...).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS specific rules, e.g. invalid instance types or regions. Pinned so lint
# results are reproducible; Dependabot does not update this, bump it manually.
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
