---
# GitHub Agentic Workflow (gh-aw). Source file; compiled to ci-doctor.lock.yml.
# Edit here, run `gh aw compile`, commit both. See docs/agentic-workflows.md.
description: Investigate failed CI runs on main and open an issue with a root-cause analysis.

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]

# Only act on failures, and only once the owner has opted in.
if: vars.AGENTIC_WORKFLOWS_ENABLED == 'true' && github.event.workflow_run.conclusion == 'failure'

permissions:
  contents: read
  actions: read
  issues: read
  pull-requests: read

engine: copilot
timeout-minutes: 15

network: defaults

tools:
  github:
    toolsets: [default, actions]

safe-outputs:
  create-issue:
    title-prefix: "[ci-doctor] "
    labels: [ci]
    max: 1
---

# CI doctor

The workflow run ${{ github.event.workflow_run.html_url }} (run id
${{ github.event.workflow_run.id }}) of the `CI` workflow failed on `main` in
`${{ github.repository }}`.

Investigate it:

1. List the jobs of the run and find the failed ones.
2. Download and read the logs of the failed steps. Focus on the first real
   error, not the cascade after it.
3. Look at the commit that triggered the run
   (`${{ github.event.workflow_run.head_sha }}`) and the files it changed.
4. Check whether an open issue with the `[ci-doctor]` prefix already covers
   the same failure. If it does, do nothing.

Then open ONE issue containing:

- **Summary**: one or two sentences on what failed.
- **Failed jobs and steps**: names and a short excerpt of the decisive log lines.
- **Likely root cause**: your best analysis, clearly marked as a hypothesis
  when you are not sure (flaky test, dependency update, infrastructure, code bug).
- **Suggested fix**: concrete next steps or a code change suggestion.

Rules:
- Never use the em dash character; use a plain dash.
- Never include secrets or tokens from logs in the issue.
- If the failure is clearly transient (for example a registry timeout), say so
  and recommend a re-run instead of a code change.