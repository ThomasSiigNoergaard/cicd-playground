#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Offline checks for every Terraform stack: fmt, init (no backend), validate
# and tflint. Needs no AWS credentials. Used by CI and by developers:
#
#   bash scripts/terraform-check.sh
#
# Windows: use scripts/terraform-check.ps1 instead.
# -----------------------------------------------------------------------------
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
tflint_config="$root/terraform/.tflint.hcl"
stacks=(
  terraform/bootstrap
  terraform/modules/app
  terraform/environments/dev
  terraform/environments/prod
)

echo "==> terraform fmt -check"
terraform fmt -check -recursive -diff "$root/terraform"

if command -v tflint > /dev/null; then
  have_tflint=true
  # Installs the plugins declared in .tflint.hcl (once, shared by all stacks).
  tflint --init --config="$tflint_config"
else
  have_tflint=false
  echo "WARN: tflint not found, skipping lint (install: https://github.com/terraform-linters/tflint)"
fi

for stack in "${stacks[@]}"; do
  echo "==> $stack"
  pushd "$root/$stack" > /dev/null
  # -backend=false: install providers/modules only, never touch remote state.
  # -lockfile=readonly: fail instead of silently changing .terraform.lock.hcl.
  if [ -f .terraform.lock.hcl ]; then
    terraform init -backend=false -input=false -lockfile=readonly > /dev/null
  else
    terraform init -backend=false -input=false > /dev/null
  fi
  terraform validate
  if [ "$have_tflint" = true ]; then
    tflint --config="$tflint_config" --format=compact
  fi
  popd > /dev/null
done

echo "All Terraform checks passed."
