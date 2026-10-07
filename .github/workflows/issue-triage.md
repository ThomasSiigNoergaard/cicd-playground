---
# GitHub Agentic Workflow (gh-aw). This Markdown file is the SOURCE; the
# runnable workflow is the compiled `issue-triage.lock.yml` next to it.
# Edit this file, then run `gh aw compile` and commit both files.
# See docs/agentic-workflows.md for how this works and how to enable it.
description: Triage newly opened issues - label them and leave a short helpful comment.

on:
  issues:
    types: [opened, reopened]
  workflow_dispatch:

# Off by default: the workflow only runs once the owner has configured the
# COPILOT_GITHUB_TOKEN secret and set this repository variable to 'true'.
if: vars.AGENTIC_WORKFLOWS_ENABLED == 'true'

# The agent itself only gets READ access. Every write (labels, comments)
# goes through `safe-outputs`, which runs in a separate, scoped job.
permissions:
  contents: read
  issues: read

engine: copilot
timeout-minutes: 10

network: defaults

tools:
  github:
    toolsets: [issues, labels]

safe-outputs:
  add-labels:
    allowed: [bug, enhancement, documentation, question, security, ci, terraform, dotnet]
    max: 3
  add-comment:
    max: 1
---

# Issue triage

You are a triage assistant for the repository `${{ github.repository }}`, a
hands-on learning repo for CI/CD with a .NET 9 API, GitHub Actions, security
tooling and Terraform on AWS ECS Fargate.

Triage issue #${{ github.event.issue.number }}.

1. Read the issue title and body with the GitHub tools.
2. Choose up to three labels from the allowed list that best describe it:
   - `bug`, `enhancement`, `documentation`, `question` for the kind of issue
   - `security` for anything security-sensitive (if it looks like an actual
     vulnerability, do NOT discuss details; point to SECURITY.md instead)
   - `ci`, `terraform`, `dotnet` for the area of the repo involved
3. Add a single short, friendly comment that:
   - summarises the issue in one sentence,
   - points to the most relevant files or docs (for example `docs/oidc.md`,
     `terraform/modules/app`, `.github/workflows/ci.yml`),
   - asks for any missing information needed to act on it.

Rules:
- Never use the em dash character; use a plain dash.
- Do not invent facts about the repo; only reference files you have seen.
- If the issue is spam or empty, add no labels and no comment.