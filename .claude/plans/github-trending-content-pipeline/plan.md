# GitHub Trending → 人工审核 → 微信草稿同步

**Status**: IN_PROGRESS
**Created**: 2026-10-04
**Last Updated**: 2026-10-04

## 目标

每天抓取 GitHub Elixir Trending 日榜前 10，生成带封面的公众号 Markdown 草稿；自动验证数据和内容格式后创建/更新 GitHub PR，供人查看、评论、编辑、提出修改并批准。只有合并到默认分支并由有权限的人显式触发受保护的同步工作流后，才调用微信公众号 API 创建或更新**草稿箱**文章。正式发表仍由人在公众号后台完成。

## 现状与边界

- 已有：`content/TEMPLATE.md` / `content/README.md`、Req 0.7.4、LazyHTML 0.1.13（目前仅 test）、Python 微信 API 试验脚本、一次手动生成的 2026-10-03 Trending 示例草稿和封面。
- 尚无：Trending 抓取器、内容生成器/校验器、PR 自动审核流程、生产 Markdown → 微信 payload 的同步程序。
- **MVP 不做**：Phoenix 审稿 UI、用户/角色数据库、Oban、评论自动交给 LLM 改稿、自动公开发表或群发。
- 内容源仍是 `content/drafts/*.md`；GitHub PR 是审核界面及审核记录。文章和 asset slug 必须按日期唯一（例如 `github-elixir-trending-20261004`），避免每天生成时覆盖 `content/assets/<slug>/cover.jpg` 或改变历史文章引用的封面；文件名前缀仍遵循 `YYYY-MM-DD-<slug>.md`，如 `2026-10-04-github-elixir-trending-20261004.md`。同日重跑不能静默覆盖已审核/合并文件。
- 微信 API 的创建/更新草稿和“公开发表”是两个动作；当前公众号没有 `freepublish/*` 权限，发布动作保留为后台人工操作。

## Breadboard：执行路径与信任边界

```text
GitHub Actions schedule / workflow_dispatch (无微信凭证)
  → `mix writing.trending.fetch` (Req GET GitHub HTML)
  → `Writing.Trending.Parser` (LazyHTML selectors；校验至少 10 条)
  → `Writing.Content.TrendingDraft` (确定性渲染 Markdown + Pillow 封面)
  → `mix writing.content.validate` (frontmatter / 约束 / 图片 / 链接 / Top 10)
  → bot branch + GitHub PR
      → 人工 review：diff 评论、request changes、网页直接编辑或本地 push
      → PR CI 重新验证，无微信 secret
      → 人工批准并 merge
  → 人工 workflow_dispatch 输入已合并 slug
      → `wechat-draft` GitHub Environment 等待授权 reviewer
      → 从默认分支取已合并版本，再次 validate
      → Req 调微信 token / 上传封面 / draft add 或全量 update / 回读验证
      → 回写 draft_media_id、thumb_media_id，提交 metadata-only 变更
  → 人工登录公众号后台确认最终发表
```

信任边界：抓取和 PR 校验一律不持有微信公众号密钥；唯一带微信 secrets 的 job 必须是人工触发、限定默认分支、通过 environment protection 后的草稿同步 job。任何 GitHub PR 内容都当作不可信输入校验，不运行它提供的脚本，也不使用带密钥的 `pull_request_target`。

## 实施任务

### Phase 1 — 抓取与可重复解析 [COMPLETED]

- [x] [P1-T1][direct] **1.1 定义 Trending 数据边界**：建立 `Writing.Trending.Repository` 数据结构，至少包含 `rank`、`full_name`、`url`、`description`、`stars`、`stars_today`、`language`、`observed_at`、`source_url`；缺值与数值 0 要区分。锁定页面顺序为榜单顺序，不按今日 Stars 二次排序。— 用 struct 表示单条观察；`stars_today` / `forks` 可为 nil，保留与 0 的区别。
- [x] [P1-T2][direct] **1.2 封装 HTTP 获取**：增加 `Writing.Trending.GitHub`，通过现有 Req 获取 `/trending/elixir?since=daily`；检查状态码与合理响应类型，设置请求超时/User-Agent，处理 403/429、超时、非 200 与临时错误。只在 safe GET 上使用有限重试，不把 challenge/错误页当成空榜单。— `Writing.Trending.GitHub.fetch/3` 校验 range/language、仅接受 HTML 响应，并返回 URL/UTC 观测时间；Req 配置可注入用于测试。
- [x] [P1-T3][direct] **1.3 实现 HTML 解析与 fail-closed 校验**：增加 `Writing.Trending.Parser`，使用 CSS 选择器定位 repo card 并抽取字段；提升现有 LazyHTML 依赖到应用运行范围（不新增另一款 HTML parser），解析失败、有效记录少于 10、重复 repo、仓库 URL 主机不正确或必需字段缺失时返回明确错误，不输出部分草稿。— 只解析 `article.Box-row`，取页面顺序前十；校验链接组件和必需 Stars，并将 daily stars 的缺失保留为 nil。LazyHTML 转为运行依赖。
- [x] [P1-T4][test] **1.4 固定页面契约测试**：在 `test/fixtures/github_trending/` 加经过筛选的代表性 HTML fixture；覆盖至少十项、千位逗号、Unicode、description 缺失、今日 0 stars、导航/赞助内容、页面空壳/挑战页/markup 变化。使用 Req.Test 模拟 HTML 响应、403/429/5xx、连接错误；测试不得访问公网。— 加入固定 Trending HTML fixture 及 parser/Req client 测试；`mix test test/writing/trending` 12 tests passed。
- [x] [P1-T5][test] **1.5 提供 Mix fetch task**：增加 `mix writing.trending.fetch`，支持 language/since、`--dry-run`/JSON 输出和来源/观测时间；抓取时刻用 UTC，文档注明 `since=daily` 是 GitHub 页面窗口而不是承诺的用户本地自然日。文章日期用 UTC，workflow 选择 UTC 非整点时间。测试和本地预览默认只打印或写临时目录，只有明确的 generate 模式才写 `content/drafts/`。— 新增 `mix writing.trending.fetch`，默认只读，支持 `--language` / `--since` / `--format text|json` 和 `--dry-run`。

### Phase 2 — 草稿生成与内容验证 [IN_PROGRESS]

- [x] [P2-T1][direct] **2.1 实现确定性 Markdown renderer**：在 `Writing.Content` 边界按模板生成每日 Top 10 草稿，描述仅使用抓取字段，不编造项目功能；清楚标注抓取时间、GitHub 页面顺序与榜单不是“今日增量排序”。正文不生成 `<a>` 或 Markdown 超链接，来源 URL 放 `content_source_url`。— 新增 `Writing.Content.TrendingDraft.render/2`，验证前十顺序，产生日期唯一 slug/frontmatter；清理简介中的外链/Markdown 符号，来源限定为 HTTPS github.com。
- [ ] [P2-T2][direct] **2.2 实现封面生成**：增加版本固定的 `scripts/requirements.txt`（至少 Pillow）和可重复运行的封面生成脚本，输出 `content/assets/<slug>/cover.jpg`；CI 安装明确版本，封面尺寸/可读性固定，验证 jpg/png 且 `<2MB`。同一日期输入生成确定的路径和可预测输出，不覆盖其他文章资源。
- [ ] [P2-T3][direct] **2.3 实现安全文件落盘与重复运行语义**：slug 按日期唯一（如 `github-elixir-trending-20261004`），文件名按仓库既有规则为 `YYYY-MM-DD-<slug>.md`，封面位于 `content/assets/<slug>/cover.jpg`。若草稿或相同日期 PR 已存在，默认停止或仅更新同一未合并 bot PR，不覆盖合并/人工修改的文章。并发 workflow 用同一 concurrency group 串行化。
- [ ] [P2-T4][test] **2.4 增加 draft validator**：验证 frontmatter 必填字段和格式、title ≤32、author ≤16、digest ≤120、slug/文件名匹配、日期有效、cover 文件存在/大小合规、正文非空且不含链接、正好 10 个唯一 repo 条目及 source URL。解析范围限于模板实际使用的 frontmatter 子集；重复键、未知/歧义语法应失败，不能静默接受错误数据。
- [ ] [P2-T5][test] **2.5 提供 Mix generate/validate tasks**：生成命令支持临时目录、指定日期、输入 fixture/snapshot；validate 命令返回非零退出码供 CI 阻断。将 2026-10-03 的人工样例用于 renderer/validator 的格式参考，不把其当前榜单数字当成永久快照基准。
- [ ] [P2-T6][test] **2.6 内容生成测试**：ExUnit 覆盖排序、中文转义、标题/摘要边界、十项不足/重复项、恶意/格式异常字段转义、已有文件不覆盖、封面缺失/超大、内文链接拦截及 deterministic output。

### Phase 3 — GitHub PR 人工审核 [PENDING]

- [ ] [P3-T1][direct] **3.1 增加 daily workflow**：新增独立的 `.github/workflows/github-trending.yml`，提供 schedule（UTC 非整点，明确标注尽力而为）和 workflow_dispatch（dry-run/手动重新抓取）；安装 BEAM，运行 fetch → generate → validate。
- [ ] [P3-T2][security] **3.2 生成或更新审核 PR**：仅对当天唯一 bot 分支创建/更新 PR；PR body 列出来源 URL、抓取时间、Top 10 数量、校验结果和人工 review checklist；权限最小化为必需的 `contents: write` / `pull-requests: write`。无变更则不创建空 PR。
- [ ] [P3-T3][security] **3.3 增加独立 PR validator workflow**：针对内容与生成器相关路径运行只读检查，权限 `contents: read`；不得暴露微信 secrets，不 checkout/执行 PR 提供的任意脚本，不使用 `pull_request_target`。验证 GITHUB_TOKEN 建立 PR 时的 workflow approval 行为；若阻断正常 review/check，才配置最小权限 GitHub App token，并记录其安装权限和轮换步骤，不默认使用宽权限 PAT。
- [ ] [P3-T4][direct] **3.4 明确 review/revision 操作**：审核者用 inline review comments、Request changes 或 GitHub 网页编辑提交修改；PR 更新后自动重新执行校验。MVP 不把文字评论自动交给 LLM；如需 AI 改稿，作为后续独立功能，必须给出可检查 diff 并重新人工批准。
- [ ] [P3-T5][security] **3.5 配置合并门禁与内容历史**：要求 PR review/所有检查通过后才合并；已合并的文章和资源不由 daily job 改写。检查第一次由 GITHUB_TOKEN 创建 PR 的 run 审批提示以及更新 PR 行为，并将操作步骤写入内容自动化说明文档。

### Phase 4 — 人工授权后同步到微信公众号草稿箱 [PENDING]

- [ ] [P4-T1][security] **4.1 实现 Markdown → 微信 article 转换**：建立 `Writing.WeChat`/`Writing.Content` 边界，将已合并 Markdown 转成 API 所需完整 article payload（title/author/digest/content/thumb/comment fields/source URL）；正文 Markdown heading、代码块等按可控规则转换为 HTML，转义仓库描述和名称，拒绝微信不支持/带链接内容。HTTP 使用 Req，不复用硬编码 `wx_draft_chain.py` 的生产 payload。
- [ ] [P4-T2][security] **4.2 实现微信 Req client**：实现稳定 token 获取/缓存、永久封面素材上传、`draft/add`、`draft/update` 和回读验证；配置只从运行时环境读取公众号专用凭据，正确处理接口成功返回形状差异、token 失效、白名单/配额错误。更新总是提交全量 article，不使用 `draft/get` 回传 HTML 作为本地内容真源。
- [ ] [P4-T3][security] **4.3 设计草稿同步任务**：增加仅接受已合并文章 slug 的 `mix writing.wechat.sync_draft`。无 `draft_media_id` 时才 add；已有 ID 时 update；已知最终结果前失败时输出可恢复状态和安全诊断，成功后更新 Markdown frontmatter 中的 `draft_media_id` / `thumb_media_id`。不提供自动删除草稿、不调用 freepublish/mass API。
- [ ] [P4-T4][security] **4.4 保证远端副作用可恢复**：保存授权者、目标 slug、合并 SHA、操作类型、执行时间和接口结果（不记 secret/token）；API 返回 media_id 后立即持久化。若 API 成功但 metadata commit 失败，进入人工恢复步骤：先查询草稿箱并匹配已批准文章，确认现有 media_id 后补写回；绝不盲目重试 `draft/add`。同步必须检查文章仍是同一批准版本，防止审批后内容改变。
- [ ] [P4-T5][security] **4.5 增加受保护的人工 workflow**：新增独立 `.github/workflows/wechat-draft.yml`，只允许 workflow_dispatch 且目标为默认分支，输入 slug/明确 add-or-update 行为；job 使用 `wechat-draft` environment，保护规则通过后才取 `WECHAT_APPID` / `WECHAT_APP_SECRET` 等 environment secrets。对 environment reviewers/防自审做人工设置并验证 repo visibility/plan 支持；不支持时停用自动 sync，要求管理员在 runner 外手动运行并保留审计记录。
- [ ] [P4-T6][security] **4.6 回写 media IDs**：同步成功后只提交 frontmatter 元数据变更（或生成 metadata-only PR，由人确认），不回写微信规范化后的正文；处理并发更新/分支冲突时停止且不再次创建草稿。
- [ ] [P4-T7][security] **4.7 保留正式发表人工操作**：结果页/Actions summary 明确显示草稿标题、media_id、公众号后台检查步骤；因当前账号 `freepublish/*` 返回 48001，不实现自动公开发布。文章正式发表后仍按 `content/README.md` 流程补 `published_at` / `article_url` 并移动到 `content/published/`。

### Phase 5 — 全链路验证、运行手册与安全复核 [PENDING]

- [ ] [P5-T1][direct] **5.1 本地无副作用验证**：用 HTML fixture 执行 Mix fetch/generate/validate，确认生成文件、封面和 PR diff；重复运行不会覆盖已有内容；断网/挑战页/解析少于 10 条不产生 draft/PR 内容更新。
- [ ] [P5-T2][direct] **5.2 GitHub 沙箱验证**：workflow_dispatch dry-run → 实际生成测试 PR → 人工 inline comment/直接编辑 → 检查更新触发 validator → request changes → 批准合并；验证 secrets 从未进入 PR job 日志或 artifacts。
- [ ] [P5-T3][direct] **5.3 WeChat 的人工批准 E2E**：先运行只读权限探测；使用专门测试文章和人工 approved environment job，执行一次 draft add + 回读；再次运行对同一 media_id 做完整 update，确认草稿数量不增加、标题/封面/正文回读符合预期。此步骤会创建真实公众号草稿，必须由用户显式批准后执行。
- [ ] [P5-T4][test] **5.4 故障恢复测试**：模拟 API 失败、草稿已创建但 Git 回写失败、重复 workflow_dispatch、封面重传、无权限和微信 48001，确认不会无提示重复 add；为人工恢复保留足够但不含凭据的诊断信息。
- [ ] [P5-T5][test] **5.5 完成项目验证**：`mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix test`、`mix precommit`；验证 `MIX_ENV=prod mix compile`（特别是 LazyHTML 运行依赖）；验证 workflow YAML、权限和默认分支保护；更新 `content/README.md`/运行手册。

## 关键风险与控制

1. **Trending 页面不是稳定 API**：selector 变化或 GitHub challenge 页必须失败并告警，不生成看似成功的半成品；保留脱敏 fixture 与来源时间。
2. **自动内容可能出现未经证实的表述**：MVP 只从页面事实/README 生成候选，不把 LLM 生成当事实；review/merge 是人工责任点。
3. **公众号创建不可随意撤销**：只有受保护的手动 job 能访问 credentials；重试优先 update 已关联 media_id；处理 API 成功后 git 写失败的恢复窗口。
4. **GitHub Actions token 有事件抑制与审批行为**：schedule 在默认分支运行且可能延迟；bot PR 的 checks 需要实测批准行为。不要借用发布工作流的 deploy secrets 或宽权限 token。
5. **人工批准粒度**：PR merge 只批准仓库内容；workflow environment approval 才授权产生微信公众号副作用；公众号后台“发表”是第三个、独立人工步骤。

## 验收标准

- 正常 fixture/有效 live response 会生成 10 个唯一 repo 的规范草稿与封面；每日重复执行幂等；异常页面不会覆盖已有稿。
- 人工可以在 GitHub PR 看 diff、逐段评论、直接修订，修订重新通过自动检查后再批准合并。
- PR 验证和日常抓取均没有微信公众号 secrets，也不会调用任何写接口。
- 只有默认分支上对已合并 slug 的人工 dispatch、经 protected environment 授权后，才创建或更新微信草稿；结果关联 media_id 并回写到真源 Markdown。
- 同步 job 不调用 `freepublish/*` 或群发接口；正式发表仍由人在公众号后台完成。
- 所有 parser、renderer、validator 和微信请求单测使用固定 fixture/Req.Test，不依赖外网；`mix precommit` 全绿。

## 研究依据

- 本计划代码证据：`research/codebase-and-content.md`
- GitHub Actions 事件/权限/环境：`research/github-actions.md`
- Trending 页面和解析边界：`research/trending-parser.md`
- 微信草稿 API、实测权限与副作用：`research/wechat-and-approval.md`
- 官方参考：[GitHub workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)、[GITHUB_TOKEN permissions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)、[GitHub environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)、[Req 0.7.4](https://hexdocs.pm/req/Req.html)、[Req.Test 0.7.4](https://hexdocs.pm/req/Req.Test.html)、[LazyHTML 0.1.13](https://hexdocs.pm/lazy_html/LazyHTML.html)、[Trending API discussion](https://github.com/orgs/community/discussions/161519)。
