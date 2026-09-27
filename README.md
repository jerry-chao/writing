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
