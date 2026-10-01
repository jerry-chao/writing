---
# 复制本文件到 content/drafts/ 后重命名为 YYYY-MM-DD-<slug>.md
# 尖括号占位符必须替换或删除；带「脚本回写」注释的字段不要手填。

title: <标题，≤32 字>              # 必填，超长微信会拒
author: <作者，≤16 字>             # 必填
digest: <摘要，≤120 字>            # 必填，留空则由微信抓正文前 54 字
slug: <kebab-case 短标识>          # 必填，与文件名 slug 一致；assets 子目录名
date: <YYYY-MM-DD>                # 必填，初稿日期
cover: content/assets/<slug>/cover.jpg   # 必填，相对仓库根；jpg/png <2MB

# 可选
tags: []
content_source_url:               # 「阅读原文」，必须是公网 http/https；localhost 报 41039
need_open_comment: 0
only_fans_can_comment: 0

# 脚本回写，勿手填
draft_media_id:                  # draft/add 返回的 media_id；后续只更新此草稿，不再新建
thumb_media_id:                  # 封面永久素材 media_id
published_at:                    # 人工在后台点「发表」的日期
article_url:                     # 永久链接 https://mp.weixin.qq.com/s/...
---

正文从这里开始，标准 Markdown。

一级标题会作为公众号正文里的 `h3` 渲染，所以**不要**用 `#` 当文章标题 ——
文章标题由 frontmatter 的 `title` 提供。推荐从段落开始，需要分节时用 `##`。

正文配图用相对本文档的标准 Markdown 路径（注意与 `cover` 的仓库根相对写法不同）：

```markdown
![说明](../assets/<slug>/inline.png)
```

发布时图片会被换成 `media/uploadimg` 返回的 `mmbiz.qpic.cn` 地址；
不要使用 Markdown 超链接。需要展示 GitHub 仓库地址时，将地址写成行内代码，
例如 `` `https://github.com/owner/repo` ``；这样地址可见但不可点击。
