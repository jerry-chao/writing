# content/ — 文章源文件

这里是**待发布与已发布图文内容的唯一真源**：一篇 Markdown = 一篇公众号文章。
后台草稿箱是它的下游产物，不要把草稿当作编辑起点（原因见 [写作约束](#写作约束微信侧硬限制)）。

## 目录结构

```
content/
├── README.md          # 本文件：规范
├── TEMPLATE.md        # 新文章模板，复制到 drafts/ 使用
├── drafts/            # 待发布 / 草稿中
│   └── 2026-09-27-<slug>.md
├── published/         # 已在公众号后台「发表」，只增不改
│   └── 2026-09-27-<slug>.md
└── assets/            # 封面与正文配图，按 slug 一一对应
    └── <slug>/
        ├── cover.jpg
        └── *.png
```

**状态即目录**：`drafts/` ↔ `published/` 靠 `git mv` 流转，不在 frontmatter 里存 `status`
（避免两处状态打架）。图片不进 git LFS，直接提交二进制，仓库体积自己心里有数。

## 新建一篇文章

```bash
cp content/TEMPLATE.md content/drafts/$(date +%F)-my-topic.md
mkdir -p content/assets/my-topic
$EDITOR content/drafts/$(date +%F)-my-topic.md
```

文件名 = `YYYY-MM-DD-<slug>.md`，`<slug>` 用 kebab-case，与 frontmatter 的 `slug` 字段一致，
也用作 `content/assets/<slug>/` 目录名。`date` 是初稿日期，后续修订不改它。

## frontmatter 字段

| 字段 | 必填 | 约束 / 说明 |
|---|---|---|
| `title` | ✅ | ≤32 字，公众号硬限制，超长直接被拒 |
| `author` | ✅ | ≤16 字 |
| `digest` | ✅ | ≤120 字（摘要），留空则微信抓正文前 54 字 |
| `slug` | ✅ | 与文件名一致，`assets/` 子目录名 |
| `date` | ✅ | `YYYY-MM-DD` 初稿日期 |
| `cover` | ✅ | 仓库根相对路径，jpg/png <2MB（走 `material/add_material`） |
| `tags` | | 列表，纯本地分类，不传给微信 |
| `content_source_url` | | 「阅读原文」，**必须公网可访问** http/https；localhost → `41039` |
| `need_open_comment` | | 默认 `0` |
| `only_fans_can_comment` | | 默认 `0` |
| `draft_media_id` | 脚本回写 | `draft/add` 返回的草稿 media_id，见 [生命周期](#生命周期) |
| `thumb_media_id` | 脚本回写 | 封面永久素材 media_id |
| `published_at` | 脚本回写 | 后台点「发表」的日期 |
| `article_url` | 脚本回写 | 永久链接 `https://mp.weixin.qq.com/s/...` |

带「脚本回写」的行由发布脚本在成功后写回文件，**不要手填**——填错会让脚本更新到别人的草稿上。

### 路径约定（两类路径故意不同）

| 位置 | 写法 | 原因 |
|---|---|---|
| frontmatter `cover` | `content/assets/<slug>/cover.jpg` | 仓库根相对。脚本从仓库根读盘，文件在 `drafts/`↔`published/` 之间移动也不用改 |
| 正文配图 | `![](../assets/<slug>/inline.png)` | 相对**文章文件**的标准 Markdown 路径，编辑器与 GitHub 预览才能正常渲染 |

正文里**不要**写绝对路径或外链 URL：外链图片会被微信过滤，发布时必须换成
`media/uploadimg` 返回的 `mmbiz.qpic.cn` 地址。

## 生命周期

```
① 写稿         content/drafts/2026-09-27-slug.md
② 建草稿       draft/add → 回写 draft_media_id / thumb_media_id
③ 迭代         改 Markdown → draft/update 同一个 draft_media_id
④ 发表         人工在 mp.weixin.qq.com 草稿箱点「发表」
⑤ 归档         补 published_at / article_url → git mv 到 published/
```

两条铁律：

- **`draft_media_id` 必须回写并留在文件里。** 微信 `draft/*` 没有 delete 接口，草稿只增不减。
  丢了 media_id 就只能新建草稿，旧草稿要去后台人工删。
- **`published/` 只增不改。** 已发表的文章以本地 Markdown 为准；需要修订就复制一份新的
  到 `drafts/` 当新文章发，不要原地改 `published/` 里的文件。

第 ④ 步目前只能人工做：账号未认证，`freepublish/*` 与 `mass/*` 全部 `48001`。
详见 [`.claude/research/wechat-mp-article-publish-api.md`](../.claude/research/wechat-mp-article-publish-api.md)。

## 变更规则

写脚本时按这张表判定「一次提交里文件该怎么变」：

| 动作 | 改哪个文件 | 注意 |
|---|---|---|
| 改正文/标题/摘要 | `drafts/<file>.md` | 同步 `draft/update`，`articles` 必须**全量**提交（稀疏更新被服务端拒） |
| 换封面 | 覆盖 `assets/<slug>/cover.jpg` + 提交 | 重新 `add_material` 并回写新 `thumb_media_id`；旧素材用 `del_material` 清掉 |
| 加正文配图 | 放 `assets/<slug>/`，Markdown 里引用 | 发布时转成 `media/uploadimg` 的 `mmbiz.qpic.cn` URL 再提交 |
| 首次建草稿 | 回写 `draft_media_id` / `thumb_media_id` | 与正文改动**同一次提交**，避免文件与草稿失联 |
| 发表后归档 | 补 `published_at` / `article_url` + `git mv` | 用 `git mv` 保留改名历史，不要「删一个建一个」 |
| 弃稿 | `git rm` 文件，或移到 `content/drafts/` 外 | 后台草稿同步人工删 |

推论：**Markdown 是真源，`draft/get` 回读的内容不是。** 微信会改写 HTML 且改写不幂等，
把回读内容写回去会逐步侵蚀排版（实测每次回读多 3 字符）。永远「本地改 → 整篇提交」。

## git 约定

内容改动与代码改动分开成 commit，别混在一个 `feat:` 里：

```
content: 新增 <slug> 草稿                # 新建文件
content(<slug>): 补第三节              # 正文/元数据编辑
content(<slug>): 换封面 v2             # 资源替换
content(<slug>): 发布并归档            # 回写 media_id/article_url + git mv 到 published/
```

一条文章一次提交；资源与 frontmatter 回写合成一次提交，别拆成「先加图后改引用」。

## 写作约束（微信侧硬限制）

写作时就避开这些，等发布时被拒或被静默改写就晚了：

- **正文不能有超链接。** `<a>` 标签被微信**整段剥除**，6 种写法无一存活（含腾讯自家域名）。
  唯一的可点击外链通道是 `content_source_url`（阅读原文），且必须是公网 URL。
  GitHub Trending 文章可用行内代码展示仓库 URL 纯文本，不要写 Markdown 链接或裸 URL。
- **正文图片必须走 `media/uploadimg`。** 外链图片会被过滤；封面另走
  `material/add_material`（永久素材）。两套接口别混。
- **正文 <2 万字符、<1MB，不含 JS。** 中文字数按字符计，标题 ≤32、摘要 ≤120。
- **JSON 不能把中文转成 `\uXXXX`**（Python 侧用 `json.dumps(..., ensure_ascii=False)`）。
- **`draft/update` 返回的 `40007 invalid media_id` 是误导性错误码**，真实原因通常是
  `articles` 缺必填字段。别当成「草稿已失效」去重建，会陷入
  「重建 → 再更新 → 再 40007」的死循环。
- **接口返回形状不一致**：`draft/add` 成功无 `errcode` 字段，`draft/update` 成功带
  `errcode: 0`。判失败要看「`errcode` 存在且 ≠ 0」。

## 相关文件

| 路径 | 用途 |
|---|---|
| `content/TEMPLATE.md` | 新文章模板 |
| `.claude/research/wechat-mp-article-publish-api.md` | 微信 API 全量研究 + 本机实测结论（权限矩阵、错误码、HTML 改写行为） |
| `scripts/wx_common.py` | token / 上传 / draft 调用的共享封装（`succeeded/1` 判成败的坑在这里） |
| `scripts/wx_draft_chain.py` | 建草稿链路验证，正文目前仍是硬编码，待改为读 `content/drafts/` |
| `scripts/wx_smoke_test.sh` | 只读权限探测；写实现前先跑它确认权限 |
