# GitHub Agentic Workflows (gh-aw)

[GitHub Agentic Workflows](https://github.github.com/gh-aw/) let you write a
workflow in **Markdown**: YAML front matter for triggers, permissions and tools,
and natural language for what the AI agent should do. The `gh aw` CLI compiles
each `.md` into a hardened, regular GitHub Actions workflow (`.lock.yml`).

This repo has three, all **off by default**:

| Source | Trigger | What it does | Writes via safe-outputs |
| --- | --- | --- | --- |
| [`issue-triage.md`](../.github/workflows/issue-triage.md) | issue opened/reopened | Labels the issue and posts a short helpful comment | up to 3 labels, 1 comment |
| [`ci-doctor.md`](../.github/workflows/ci-doctor.md) | `CI` failed on `main` | Reads the failed logs and opens an issue with a root-cause analysis | 1 issue |
| [`weekly-repo-status.md`](../.github/workflows/weekly-repo-status.md) | weekly (Monday) | Summarises activity, CI health and security alerts | 1 issue, older reports closed |

## Security model (why this is safe to run on a public repo)

- **The agent has read-only permissions.** The `permissions:` block in the
  front matter applies to the agent job, and none of them are `write`.
- **Writes go through `safe-outputs`.** The agent can only *request* an action
  (add label X, create issue Y). A separate job without AI validates the request
  against the allow list (`allowed:` labels, `max:` counts, title prefixes) and
  then performs it with a short-lived, narrowly scoped token.
- **Network egress is firewalled.** `network: defaults` allows only the
  endpoints the engine needs, so a prompt-injected agent cannot exfiltrate data
  to an arbitrary host.
- **Untrusted input is sanitised.** Issue titles and bodies are passed to the
  agent as sanitised text, never interpolated into shell scripts.
- **The lock file is pinned and reviewable.** Every action in `.lock.yml` is
  SHA-pinned (recorded in `.github/aw/actions-lock.json`). The lock files are
  marked `linguist-generated` in `.gitattributes`, so PR diffs collapse them.

## Enable them

1. Create a **fine-grained personal access token** with the account
   permission **Copilot Requests** (read). No repository access is needed. The
   Copilot engine uses it to call the model.
2. Store it as a repository secret and turn on the gate variable:

   ```bash
   gh secret set COPILOT_GITHUB_TOKEN --repo ThomasSiigNoergaard/cicd-playground
   gh variable set AGENTIC_WORKFLOWS_ENABLED --repo ThomasSiigNoergaard/cicd-playground --body true
   ```

3. Make sure the labels used by the triage workflow exist (already done for
   this repo, shown for reference):

   ```bash
   for l in security ci terraform dotnet; do gh label create "$l" -R ThomasSiigNoergaard/cicd-playground -f; done
   ```

4. Try it: open an issue, or run one manually with
   `gh aw run weekly-repo-status` (or `gh workflow run weekly-repo-status.lock.yml`).

Every agentic run consumes Copilot premium requests. Set
`AGENTIC_WORKFLOWS_ENABLED` to anything other than `true` to pause them all.

## Edit them

```bash
gh extension install github/gh-aw    # once
# edit .github/workflows/<name>.md
gh aw compile                        # regenerates <name>.lock.yml
gh aw compile --strict               # optional: extra security validation
git add .github/workflows/<name>.md .github/workflows/<name>.lock.yml
```

Always commit the `.md` and `.lock.yml` together; GitHub only runs the lock
file. Never hand-edit a `.lock.yml`. Do not run `gh aw init` here, it would
overwrite the hand-written Copilot instructions.

Ideas to try next: a PR reviewer that comments on Terraform plans, a docs
updater that opens a PR when the README walkthrough drifts from the workflows,
or an issue-to-PR flow using the `create-pull-request` safe output.
