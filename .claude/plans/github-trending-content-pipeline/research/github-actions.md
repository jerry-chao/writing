# GitHub Actions research

## Official documentation

- [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): `schedule` runs only for workflow files on the default branch; schedule can be delayed or dropped under load; schedule away from the top of the hour. `workflow_dispatch` is available for manual refresh/sync.
- [GITHUB_TOKEN authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication): grant minimum permissions at workflow/job level. `contents: write` and `pull-requests: write` are needed if automation pushes generated content and opens/updates a PR.
- [Workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): workflows caused by `GITHUB_TOKEN` generally do not recursively trigger other workflow runs; PR events for PRs created/updated by GITHUB_TOKEN have approval behavior. `workflow_dispatch` and `repository_dispatch` are exceptions to recursive suppression.
- [Environment protection](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment): environment secrets are unavailable to the job until protection rules pass; required reviewers / prevent-self-review availability depends on repo visibility and account plan.
- [Secure use of pull_request_target](https://docs.github.com/en/enterprise-cloud@latest/actions/reference/security/securely-using-pull_request_target): never check out or run untrusted PR code in a privileged `pull_request_target` job with secrets.

## Plan consequences

- Use one scheduled/manual workflow for fetch → generate → validate → create/update the daily article PR. Choose a non-hour UTC time and document that timing is best-effort.
- Use least-privilege token permissions, serialize runs with a concurrency group, and make the daily slug/date idempotent. PR validation is a separate read-only workflow and must not receive WeChat credentials.
- Since automated PR creation with GITHUB_TOKEN has special approval/trigger behavior, test this in the repository. If this materially impedes PR checks, use a narrowly scoped GitHub App installation token as an explicit setup task; do not silently broaden to a personal token.
- WeChat sync is a separate manually dispatched workflow on the default branch, references a protected `wechat-draft` environment, and only loads WeChat secrets after approval. Enforce that the input slug resolves to a merged article on default branch.
- Never use `pull_request_target` to validate article branches. Validation needs only to read/parse the Markdown and image, not execute PR-provided code.

## Proposed event shape

- `schedule`: one daily run, off the hour.
- `workflow_dispatch`: operator-triggered refresh, with a dry-run option for testing.
- `pull_request`: validation-only, path-filtered to generated content and relevant generator code; no secrets.
- Separate `workflow_dispatch` job for syncing an already merged article to WeChat.
