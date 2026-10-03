# Codebase and content constraints

## Findings

- `mix.exs`: Phoenix 1.8.9, Req `~> 0.5` locked to 0.7.4, LazyHTML `>= 0.1.0` currently `only: :test` and locked to 0.1.13; no Oban, no content context, no content schemas.
- `lib/writing_web/router.ex`: only `/` home route. The MVP can avoid user accounts, database work and a review LiveView by using repository PR review.
- `.github/workflows/release.yml`: existing workflow is manual release/deploy. Keep content fetch/sync workflows separate so normal article work cannot accidentally deploy the Phoenix application.
- `content/README.md`: Markdown is the article source of truth; draft state is represented by directory; file naming and slug must match; `title <= 32`, `author <= 16`, `digest <= 120`; cover path is required and image must be `<2MB`; media IDs are written back into Markdown; body links are removed by WeChat and must not be generated.
- `content/TEMPLATE.md`: required frontmatter contract, including `content_source_url` and script-managed metadata.
- `content/drafts/2026-10-03-github-elixir-trending.md` plus `content/assets/github-elixir-trending/cover.jpg`: a human-generated sample artifact usable as an initial expected-output example, not as scraper fixture truth.
- `scripts/wx_common.py` uses Python stdlib `urllib`; `scripts/wx_draft_chain.py` is hard-coded and calls live `draft/add`. Do not invoke it as production sync. Project AGENTS prefer Req for new HTTP code.

## Planning decisions

- Add pure Elixir modules under a `Writing.Trending` boundary for fetching, parsing, normalization, rendering and validation; expose them through Mix tasks for local dry runs and CI.
- Use the GitHub PR as review UI for MVP. Do not add Ecto schema or LiveView route yet.
- Keep existing Python smoke/research scripts as manual diagnostics; implement production WeChat integration in Elixir with Req or wrap already verified protocol facts behind a new Elixir module, not by extending the hard-coded test article.
- If using LazyHTML from production code, change its Mix dependency scope and verify `MIX_ENV=prod mix compile`; it is already locked, so this need not introduce a new parser package.

## Verification implications

- Unit tests must not hit GitHub or WeChat; use `Req.Test` stubs and HTML fixtures.
- Live fetch is an explicitly opted-in smoke test; WeChat side-effect tests remain manual and protected.
- Existing `mix precommit` and Phoenix test alias are the repo's verification baseline.
