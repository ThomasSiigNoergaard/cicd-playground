# Releases, PR titles and required checks

## Releases from conventional commits

[`release.yml`](../.github/workflows/release.yml) runs on every push to `main`.
It reads the commits since the last `vX.Y.Z` tag and decides the bump:

| Commit subject on `main` | Release |
| --- | --- |
| `fix: ...` | patch (`v1.2.3` -> `v1.2.4`) |
| `feat: ...` | minor (`v1.2.3` -> `v1.3.0`) |
| `feat!: ...` or a `BREAKING CHANGE:` footer | major (`v1.2.3` -> `v2.0.0`) |
| `chore:`, `docs:`, `ci:`, `build:`, `test:`, ... | no release |

If there is something to release, it tags the commit and creates a GitHub
release with a generated changelog.

The design has two stages, the same as in `tv2/agent-skills`:

1. **`version`** computes the next version in dry-run mode with only
   `contents: read`. The third-party tag action therefore can never write.
2. **`release`** calls the reusable
   [`_release.yml`](../.github/workflows/_release.yml). This is the only place
   that has `contents: write`, and it only uses the first-party `gh` CLI.

Three more details:

- **Manual bump.** Use `gh workflow run release.yml -f force_bump=minor`.
- **Release events do not trigger other workflows.** The release is created
  with `GITHUB_TOKEN`, and GitHub does not start other workflows for it. This
  prevents recursive runs. If you later want "on: release" deployments, use a
  GitHub App token instead.
- **The release is a version marker only.** The deployed artifact is still
  the image digest that `deploy.yml` builds from the same commit.

## Conventional PR titles

[`pr-title.yml`](../.github/workflows/pr-title.yml) lints the PR title, not
every commit. With **squash merge** the PR title becomes the single commit on
`main`, so the title alone decides the release.

- **Rules.** The title must use an allowed type (`feat`, `fix`, `docs`, `ci`,
  `build`, `chore`, `refactor`, `perf`, `test`, `style`, `revert`) and a lower-case
  subject.
- **Dependabot titles.** Dependabot PRs are configured to use
  `build(deps): ...`, which passes the lint and creates no release.

Configure the repo so this holds:

```bash
gh api -X PATCH repos/ThomasSiigNoergaard/cicd-playground \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true
```

## One required check: `CI - Required Checks`

Branch protection needs the exact name of every required check. As workflows
grow, that list becomes fragile: rename a job and merges are blocked forever.

So `ci.yml` ends with an **aggregator job**, `CI - Required Checks`. It:

- needs every other CI job;
- runs with `if: always()`;
- fails if any of them failed or was cancelled.

Skipped jobs count as passed, because path filters and fork PRs legitimately
skip work. Make this the **only** required check from CI. New jobs then only
need adding to its `needs:` list.

`ci.yml` also listens to `merge_group`, so the same check runs on the
temporary merge-queue branch. Without that trigger, a merge queue waits
forever for a check that never starts.

### Ruleset for `main`

```bash
gh api -X POST repos/ThomasSiigNoergaard/cicd-playground/rulesets --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "CI - Required Checks" },
          { "context": "Conventional PR title" }
        ] } },
    { "type": "code_scanning", "parameters": { "code_scanning_tools": [
        { "tool": "CodeQL", "security_alerts_threshold": "high_or_higher", "alerts_threshold": "errors" } ] } }
  ]
}
EOF
```

The approval count is `0` because you are the only maintainer. Copilot code
review (see [ai-tooling.md](ai-tooling.md)) can be added to the same ruleset.

To try a **merge queue**, edit the ruleset in the UI and add the *Require
merge queue* rule. Merge queues need an organisation-owned repo, so on a
personal account you can read the setup but not enable it. `merge_group`
support is in place for when you move the pattern to an org repo.
