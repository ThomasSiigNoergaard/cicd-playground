<#
.SYNOPSIS
  Offline checks for every Terraform stack: fmt, init (no backend), validate
  and tflint. Needs no AWS credentials. PowerShell twin of terraform-check.sh.

.EXAMPLE
  ./scripts/terraform-check.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command" }
}

$root = (git rev-parse --show-toplevel).Trim()
$tflintConfig = Join-Path $root 'terraform/.tflint.hcl'
$stacks = @(
    'terraform/bootstrap',
    'terraform/modules/app',
    'terraform/environments/dev',
    'terraform/environments/prod'
)

Write-Host '==> terraform fmt -check'
Invoke-Native { terraform fmt -check -recursive -diff (Join-Path $root 'terraform') }

$haveTflint = [bool](Get-Command tflint -ErrorAction SilentlyContinue)
if ($haveTflint) {
    Invoke-Native { tflint --init --config="$tflintConfig" }
}
else {
    Write-Warning 'tflint not found, skipping lint (install: https://github.com/terraform-linters/tflint)'
}

foreach ($stack in $stacks) {
    Write-Host "==> $stack"
    Push-Location (Join-Path $root $stack)
    try {
        # -backend=false: install providers/modules only, never touch remote state.
        # -lockfile=readonly: fail instead of silently changing .terraform.lock.hcl.
        if (Test-Path .terraform.lock.hcl) {
            Invoke-Native { terraform init -backend=false -input=false -lockfile=readonly | Out-Null }
        }
        else {
            Invoke-Native { terraform init -backend=false -input=false | Out-Null }
        }
        Invoke-Native { terraform validate }
        if ($haveTflint) {
            Invoke-Native { tflint --config="$tflintConfig" --format=compact }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host 'All Terraform checks passed.'
