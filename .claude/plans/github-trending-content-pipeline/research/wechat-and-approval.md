# WeChat draft and authorization research

## Project evidence

- `.claude/research/wechat-mp-article-publish-api.md` records live-tested permission matrix: the current official-account credentials can obtain token, access draft APIs, upload permanent material and create/update drafts; `freepublish/*` and mass-send APIs return 48001 for the current unverified account.
- The same research records that `draft/add` success returns `media_id` without `errcode`; `draft/update` success returns `errcode: 0`; do not treat the presence of `errcode` alone as failure.
- `draft/update` requires a complete article payload, not a sparse patch. The local Markdown must remain canonical because WeChat rewrites returned HTML non-idempotently.
- There is no draft-delete endpoint. A mistaken `draft/add` can leave a permanent item that must be removed manually in the official-account console.
- `content/README.md` requires `draft_media_id` and `thumb_media_id` to be written back to the Markdown after successful creation/update.

## Authorization and side-effect boundary

- Separate “merge/review approved” from “sync to WeChat draft box”. The latter is an explicit manual `workflow_dispatch` action for a slug on the default branch, gated by a protected `wechat-draft` environment and environment secrets.
- The protected job must check out the merged default-branch revision, validate its slug/path/metadata/cover and compare the commit SHA recorded in the run. No credentials are available to schedule or PR validation jobs.
- With no `draft_media_id`, call `draft/add` once; with an existing one, call `draft/update` with the complete article payload. Upload a new cover only when needed and clean orphan material carefully after checking all drafts that reference it.
- After API success, write media IDs into frontmatter and create a metadata-only commit/PR. If this write-back fails after remote success, do not blindly retry `draft/add`; recover by querying the draft list and matching the approved title/slug evidence, then persist the existing media ID.
- The current account cannot call the public publish API. Formal publication remains an operator action in the WeChat backend and is outside this automated workflow.

## Testing boundaries

- Unit tests use Req stubs and assert request paths, complete JSON fields, successful response shapes and error handling.
- No CI job hits live WeChat. One manual, operator-approved end-to-end test may create/update a dedicated test draft and verify via `draft/get`/`batchget`.
- Test and production credentials must never be mixed; secrets are GitHub Environment secrets, not PR secrets or generated content.
