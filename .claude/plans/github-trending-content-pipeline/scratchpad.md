# GitHub Trending 内容流水线 — 计划研究记录

## 范围基线

- 每日抓取 GitHub Trending 的 Elixir 语言日榜 Top 10。
- 自动生成符合 `content/TEMPLATE.md` 的 Markdown 草稿及封面，并进行本地校验。
- 通过 GitHub PR 进行人工 review、评论反馈、直接修改和版本留痕；MVP 不建 Phoenix 审稿后台，不允许模型自动批准。
- 合并后由人工显式触发受保护的 workflow，把已批准 Markdown 同步到微信公众号草稿箱。
- 公开发表仍由人工在公众号后台完成；不自动调用 `freepublish/*`。
- 内容 Markdown 继续作为仓库真源；微信 `media_id` 要回写并保存，避免重试重复建稿。

## 研究轨道

- [x] 当前代码、文章规范、微信脚本与约束核对
- [x] GitHub Actions 定时任务 / PR / 权限与触发安全
- [x] Trending 抓取、解析、失败与快照校验
- [x] 审核后公众号草稿创建/更新、授权和幂等策略
- [x] 验证路线、风险及阶段边界

## 已确认的项目证据（初步）

- `mix.exs` 已有 `:req`，没有 Oban、HTML 解析器或内容领域模块。
- `.github/workflows/release.yml` 目前只有手动发布 release / deploy workflow。
- `content/README.md` 规定 Markdown 是唯一真源；标题 ≤32、摘要 ≤120、封面必填且 <2MB；草稿 ID 应回写；正文不可含超链接。
- `scripts/wx_common.py` 与 `scripts/wx_draft_chain.py` 是 Python 测试链路，后者内容硬编码且会实际调用 `draft/add`，不能当作安全的生产同步命令直接运行。
- `.claude/research/wechat-mp-article-publish-api.md` 记载草稿 API 可用，而公开发布接口因账号认证限制不可用；草稿没有 API 删除接口。
- 当前 `WritingWeb.Router` 只有首页 route；因此采用 GitHub PR 审核可避免此阶段新增账户、认证、审核 UI 和数据库 schema。

## 决策 / 风险备忘

- GitHub Trending 是 HTML 页面，不承诺稳定的结构化 API；解析需隔离并由 fixture 覆盖，页面变更时应 fail closed，不能悄悄生成不完整 Top 10。
- Scheduled workflow 中的 GitHub token 权限最小化；PR 工作流不拿微信 secrets；公众号密钥仅放在受保护 environment。
- `draft/add` 是不可轻易撤销的副作用；同步流程需要保护环境审批、对已有关联 media_id 执行 update、在成功后可靠回写 ID。
- 暂不启用 Oban/数据库作任务队列；每日定时由 GitHub Actions 负责，只有后续需要站内调度/多用户审稿再重新评估。
- GitHub 文档确认 `schedule` 只在默认分支上的 workflow 执行，可能延迟/丢弃，因此 cron 不放整点；`GITHUB_TOKEN` 创建/更新 PR 会有 workflow approval 行为，MVP 采用显式 workflow 权限、在 PR workflow 中不使用 `pull_request_target`，并将可复跑的校验放 PR CI。
- GitHub 官方没有 Trending REST API（GitHub Community discussion）；抓取属于 HTML 页面解析，结构变化必须 fail closed。复用项目已有 `Req 0.7.4` 和 `LazyHTML 0.1.13`（当前 LazyHTML 仅 `:test`），不引入新 HTML parser；需要把 LazyHTML 提升为可用于生产代码的依赖范围。
- PR 内联评论与直接编辑满足 MVP 的人工反馈/修改；不在本计划中自动让 LLM 解释 review 评论或生成改稿，避免模型把关与人工批准混淆。
- WeChat sync 采用单独 `workflow_dispatch` + protected environment；公众号密钥只在受保护环境中提供。GitHub Environment reviewer 能否启用取决于仓库可见性/套餐，若不可用则须使用等效的管理员手动门禁，不能静默放开密钥。
- 微信 API 步骤必须将 `draft_media_id`、`thumb_media_id` 回写到 Markdown。远端 API 成功与 Git 写回无法做分布式事务，需计划恢复步骤：先查草稿箱匹配 media_id/标题，确认后续更新，不允许盲目重试 `draft/add`。
- 日榜内容与封面是每天一篇历史文章，`slug` 必须日期唯一（如 `github-elixir-trending-20261004`），否则固定资产目录会被后续每日运行覆盖；生成日期取 UTC 并显式文档化，避免 runner timezone 隐式改变路径。
