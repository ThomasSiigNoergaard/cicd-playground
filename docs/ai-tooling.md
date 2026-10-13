# AI tooling: GitHub Copilot in this repo

This repo is set up so Copilot works well **with** the repo's conventions instead of against them. The pieces:

| File | Used by | Purpose |
|---|---|---|
| `.github/copilot-instructions.md` | Copilot Chat, code review, coding agent | Repo-wide conventions: stack, build/test commands, security rules |
| `.github/instructions/*.instructions.md` | Same, but only for matching paths | Path-scoped rules via `applyTo` front matter (`terraform/**`, `**/*.cs`) |
| `.github/workflows/copilot-setup-steps.yml` | Copilot coding agent | Pre-installs .NET, Terraform and tflint, and restores packages, before the agent starts |

## Custom instructions

- **Repo-wide:** `.github/copilot-instructions.md` is added to the context of every Copilot request made in this repository. Keep it short and factual. It is a brief for a new teammate, not a style essay.
- **Path-scoped:** files under `.github/instructions/` add rules only when Copilot works on matching files, for example:

  ```markdown
  ---
  applyTo: "terraform/**"
  ---
  ```

  This keeps the Terraform rules out of the context when someone is editing C#, and vice versa.

## 1. Copilot code review (automatic, via a ruleset)

Copilot can review every PR automatically and leave comments, just like a human reviewer. It reads the custom instructions above.

1. Go to **Settings > Rules > Rulesets > New ruleset > New branch ruleset**.
2. Name it, for example `main`, and set **Enforcement status** to *Active*.
3. Under **Target branches**, choose *Include default branch*.
4. Under **Branch rules**:
   - Enable **Automatically request Copilot code review**.
   - Optionally tick **Review new pushes** and **Review draft pull requests**.
5. While you are there, also consider:
   - **Require a pull request before merging**.
   - **Require status checks to pass**, with checks such as `.NET / Build and test`, `Docker build and scan`, `Dependency review` and `fmt / validate / tflint`. The picker shows the exact names once each check has run at least once.
   - **Block force pushes**.
6. Save.

You can also request a review ad hoc: on a PR, open **Reviewers** and pick **Copilot**. Copilot leaves a "Comment" review, so it never blocks merging on its own.

## 2. Copilot Autofix for code scanning

When CodeQL (or another tool whose results are supported) raises an alert, **Copilot Autofix** proposes a fix: an explanation plus a suggested code change.

- **Enable:** **Settings > Advanced Security > Code scanning > Copilot Autofix**, set to *On* for CodeQL. Autofix for third-party tools is a separate toggle. It is free for public repos.
- **On a PR:** an alert introduced by the PR gets an Autofix suggestion as a review comment. Click **Commit suggestion**.
- **On existing alerts:** open the alert under **Security > Code scanning** and click **Generate fix**. You can also start a **security campaign** to fix many alerts at once.

To try it, introduce a deliberate issue on a branch, for example a SQL string built from user input or a `Process.Start` with a request parameter. Open a PR and watch CodeQL and Autofix respond. Do not merge it.

## 3. Assigning issues to the Copilot coding agent

The coding agent works autonomously in a GitHub Actions-powered environment. It creates a branch, commits and opens a draft PR, then iterates on your review comments.

1. Make sure the coding agent is enabled for your account under **Settings (user) > Copilot > Coding agent**. It is available on Copilot Pro, Pro+, Business and Enterprise.
2. Create an issue with a clear, scoped description and acceptance criteria. The *Feature request* template in this repo is shaped for that. Example:

   > Add a `GET /version` endpoint returning `{ version, commit }`, with an integration test. Update the README endpoint list.

3. Assign the issue to **Copilot**: in the issue sidebar, open **Assignees > Copilot**. You can also run:

   ```bash
   gh issue edit <number> --add-assignee "@copilot"
   ```

4. Copilot reacts with 👀, opens a draft PR, and links its session log so you can watch the reasoning.
5. Review the PR as usual. Mention `@copilot` in a review comment to ask for changes.
6. **Approve the workflow runs.** Workflows on Copilot's PRs do not run until a human approves them (**Approve and run workflows**). This stops an agent from running CI with your secrets unattended.

### `copilot-setup-steps.yml`

Before it starts, the agent runs the job named **`copilot-setup-steps`** (the name is required) from `.github/workflows/copilot-setup-steps.yml`. Here, the job:

- installs the .NET SDK pinned in `global.json`, Terraform and tflint;
- restores NuGet packages and initialises the tflint plugins.

The agent can therefore build, test and lint from its first step, instead of discovering tools by trial and error.

The workflow also runs on PRs that change it, and via `workflow_dispatch`, so you can verify it works. Keep its `permissions` minimal: the agent gets its own token, and this job only needs `contents: read`.

The agent's network access is firewalled by default. If it needs other hosts, configure them under **Settings > Copilot > Coding agent**.

## 4. Copilot secret scanning (generic secret detection)

Classic secret scanning matches **known token formats** from about 200 providers. **Copilot secret scanning** uses AI to also detect **generic secrets**, for example passwords in config files or connection strings, that have no fixed pattern.

1. Go to **Settings > Advanced Security**.
2. Make sure **Secret Protection** is enabled. It is free for public repos.
3. Under **Secret Protection**, enable:
   - **Push protection**, which blocks pushes that contain supported secrets.
   - **Copilot secret scanning > Generic secrets**. The setting may be shown as "Use AI detection to find additional secrets".
4. Generic secret alerts appear under **Security > Secret scanning**, in a separate **Other** / **Generic** tab.

To test it safely, use a throwaway branch. Push protection should stop a fake but realistic-looking secret, such as a GitHub PAT format string. Generic detections are reported after the push. Delete the branch afterwards, and never use real credentials.

## 5. GitHub Agentic Workflows

Besides Copilot features you switch on in settings, this repo has three **agentic workflows** built with [gh-aw](https://github.com/github/gh-aw): issue triage, a CI doctor that explains failed runs, and a weekly status report. You write them in Markdown, and `gh aw compile` turns each one into a hardened `.lock.yml`. The agent runs read-only in a sandbox with a network firewall, and every write goes through a separate, allow-listed "safe outputs" job.

They are off by default. Setup, the security model and how to edit them are in [agentic-workflows.md](agentic-workflows.md).

## Tips for working with Copilot here

- Ask Copilot Chat to "explain this workflow" on any file in `.github/workflows`. The comments are written to make those explanations richer.
- Keep `copilot-instructions.md` up to date when conventions change. Stale instructions are worse than none.
- Treat AI output like any other contribution: CI, CodeQL, dependency review and a human review still apply.
