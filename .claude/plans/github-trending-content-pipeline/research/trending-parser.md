# GitHub Trending fetch and parser research

## Findings

- GitHub Community discussion [REST API Endpoints for /explore and /trending](https://github.com/orgs/community/discussions/161519) reports that GitHub does not publish an official REST endpoint for Trending; the available page is HTML and community scraper endpoints are unofficial.
- Target page for this feature is `https://github.com/trending/elixir?since=daily`. The live fetch performed in this conversation returned language-specific repository cards containing repository name, description, total stars, forks, and daily stars. The page structure and card markup are not a stable API contract.
- Existing `Req` dependency is locked at 0.7.4. Req supports normal GET requests, response status/body inspection, retries for transient safe requests, and configurable plugs.
- Existing `LazyHTML` 0.1.13 offers HTML document parsing and CSS-selector queries, but `mix.exs` currently limits it to test environment. It can be promoted to app/runtime dependency instead of introducing a second HTML parser.
- Existing `Req.Test` can return HTML responses and model transport failures, allowing network-independent parser/client tests.

## Required parser behavior

- Parse cards based on semantic structure/selectors, not brittle positional regex over the full page.
- Extract stable values: `owner/repo`, repository URL, description (optional), total stars, forks (optional), today's added stars.
- Strip commas/whitespace and parse missing/zero values distinctly. A value missing from the card must not be silently represented as zero.
- Ignore navigation, sponsor cards, and developer cards; preserve repository card order from GitHub.
- Require the expected number of valid repositories before generation (Top 10 minimum/target), unique full names, and valid same-host repo URLs. If cards cannot be parsed, fail closed and do not create/overwrite a draft.
- Save a sanitized HTML fixture and normalized JSON snapshot (timestamp + source URL) for reproducibility. Do not commit full live responses containing irrelevant page content unless reviewed.
- Treat GitHub timeout, 403/429, non-200, bot challenge, changed selectors and partial output as visible run failures with no PR update.

## Test matrix

- Fixture: ordinary ten-or-more repository cards with commas, Unicode descriptions, missing description, zero stars today, and sponsor/navigation nodes.
- Regressions: empty page, challenge page, malformed card, duplicate repo, fewer than Top 10, network timeout, 403/429/5xx.
- Repeated daily run: same date is idempotent; never overwrite an already reviewed/merged article silently.
