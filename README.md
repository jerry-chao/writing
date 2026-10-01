# Writing

## 内容写作

待发布与已发布的图文以 Markdown 存在 [`content/`](content/README.md)，一篇 Markdown = 一篇公众号文章：

```
content/
├── drafts/      # 待发布 / 草稿中
├── published/   # 已在公众号后台发表，只增不改
└── assets/      # 封面与正文配图，按 slug 对应
```

新建文章：`cp content/TEMPLATE.md content/drafts/$(date +%F)-<slug>.md`
命名规则、frontmatter 字段、生命周期与 git 提交约定见 [`content/README.md`](content/README.md)。
发布链路的接口约束与本机实测结论见
[`.claude/research/wechat-mp-article-publish-api.md`](.claude/research/wechat-mp-article-publish-api.md)。

## GitHub Trending 自动草稿

Oban 每天按北京时间 06:00 抓取 GitHub Trending 的 Elixir 榜和全语言榜，按页面顺序整理前十；周一增加当前周榜，每月 1 日增加当前月榜，并合并成当天的一篇公众号草稿。AI 文章分析通过 Jido 生态的 ReqLLM 调用；仓库描述、Topics 和 README 仅作为分析资料。公众号正文里的仓库 URL 是行内代码形式的纯文本，不是可点击链接。

定时任务保存 Markdown 到 `content/drafts/`，创建或更新同标题的公众号草稿，并在工作树没有其他改动时创建仅含该文章的本地 Git 提交，不会推送、自动发表或群发。人工审核和发表后仍沿用 [`content/README.md`](content/README.md) 的流程。错过当天的已入队任务会跳过；失败重试仍限于原定日期。

在持续运行且已配置 PostgreSQL 的机器上设置环境变量并执行 `mix ecto.migrate` 后启动应用。至少需要配置：

| 环境变量 | 说明 |
|---|---|
| `DEEPSEEK_API_KEY` | 可选；配置后使用 OpenCode Go 兼容端点 |
| `DEEPSEEK_ENDPOINT` | 与 key 配套的 HTTPS Chat Completions 完整地址 |
| `DEEPSEEK_MODEL` | 与端点匹配的模型标识，如 `deepseek-v4-flash` |
| `TRENDING_MODEL` | 未设置 `DEEPSEEK_*` 三项时使用的 ReqLLM 模型，默认为 `openai:gpt-4o-mini` |
| 对应模型服务商的 API key | 未配置 `DEEPSEEK_*` 时使用服务商标准变量，例如 `OPENAI_API_KEY` |
| `WECHAT_MP_APPID` / `WECHAT_MP_APP_SECRET` | 公众号 API 凭据，出口 IP 还须加入公众号 IP 白名单 |
| `TRENDING_REPO_PATH` | 运行机器上的 Git 工作树路径；默认为应用启动目录 |
| `GITHUB_TOKEN` | 可选但建议配置的 GitHub Token，提升公开 API 的请求额度 |

发布机器需要有 Git 提交者身份配置；如果工作树存在其他暂存或未提交改动，任务会在创建公众号草稿前停止。数据库使用 Oban 2.24，要求 PostgreSQL 14 或更高版本。模型服务、Git 凭据和公众号权限需由部署者自行配置。

编辑已生成的 Trending Markdown 后，可运行 `mix writing.wechat.sync content/drafts/<文件名>.md` 全量同步并更新同一篇公众号草稿；正文中的图片和可点击链接会被拒绝，仓库 URL 应保留为行内代码纯文本。

## 开发

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4006`](http://localhost:4006) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
