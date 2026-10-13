---
# GitHub Agentic Workflow (gh-aw). Source file; compiled to weekly-repo-status.lock.yml.
# Edit here, run `gh aw compile`, commit both. See docs/agentic-workflows.md.
description: Weekly status report on activity, CI health, security alerts and suggested next steps.

on:
  # gh-aw "fuzzy" schedule: the compiler picks a stable random time within
  # the day so that many repos using the same workflow do not all fire at once.
  schedule: weekly on monday
  workflow_dispatch:

if: vars.AGENTIC_WORKFLOWS_ENABLED == 'true'

permissions:
  contents: read
  actions: read
  issues: read
  pull-requests: read
  security-events: read

engine: copilot
timeout-minutes: 15

network: defaults

tools:
  github:
    toolsets: [default, actions, code_security]

safe-outputs:
  create-issue:
    title-prefix: "[weekly-status] "
    labels: [documentation]
    # Older reports are closed automatically so only the latest stays open.
    close-older-issues: true
    max: 1
---

# Weekly repository status

Write a weekly status report for `${{ github.repository }}`, a learning repo
for CI/CD, supply-chain security and AI tooling.

Gather, for the last 7 days:

1. Merged and open pull requests (title, author, age). Call out Dependabot
   PRs that are waiting for review.
2. Workflow health: runs of `CI`, `Terraform`, `Deploy`, `CodeQL` and
   `Scorecard` on `main`, with their success rate and any recurring failures.
3. Open code scanning alerts grouped by severity, and open Dependabot pull requests.
4. Open issues, especially anything labelled `bug` or `security`.

Then open ONE issue titled with the current ISO week (for example
`2026-W05`) containing:

- **Highlights**: three bullets max.
- **CI/CD health**: a small table of workflow, runs, success rate.
- **Security**: alert counts by severity with links.
- **Suggested next steps**: up to five concrete, small learning tasks the
  owner could pick up next (for example "enable merge queue", "fix alert X").

Rules:
- Never use the em dash character; use a plain dash.
- Keep it short and scannable; link instead of pasting long content.
- Never list secret scanning alert contents.