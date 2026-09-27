# 公众号 API 发布文章（Research）

> 研究日期：2026-09-26 · 主题：通过微信公众号服务端 API 发布图文文章

## 摘要

公众号 API 发文章是一条固定四步流水线：取 `access_token` → 上传封面图/正文图 → `draft/add` 建草稿 → `freepublish/submit` 提交发布，再用 `freepublish/get` 轮询异步结果拿永久链接。关键约束：2025-07 起仅**企业主体已认证**账号可调 `freepublish/*`；正文里的图片 URL 必须来自 `media/uploadimg`，外链会被过滤；`freepublish` 只"发表"（不推送给粉丝、不占群发次数），要推送粉丝需另调 `message/mass/sendall`。Elixir 可直接用 Hex 包 `wechat`（hex: `wechat_sdk`）。

## 完整调用流程

```
1. GET  /cgi-bin/token?grant_type=client_credential&appid=&secret=   → access_token (TTL 7200s)
2a. POST /cgi-bin/material/add_material?type=image                  → thumb_media_id (封面，永久素材)
2b. POST /cgi-bin/media/uploadimg                                   → url (正文内图片，返回 mmbiz.qpic.cn URL)
3.  POST /cgi-bin/draft/add          {"articles":[...]}             → media_id (草稿)
4.  POST /cgi-bin/freepublish/submit {"media_id": ...}              → publish_id (异步发布任务)
5.  POST /cgi-bin/freepublish/get    {"publish_id": ...}            → publish_status / article_url
6.(可选) POST /cgi-bin/message/mass/sendall                         → 推送给粉丝（单独额度）
```

### 步骤 3 请求体（draft/add 关键字段）

```json
{
  "articles": [{
    "article_type": "news",
    "title": "标题（≤32字，别传 \\uXXXX 转义）",
    "author": "作者（≤16字）",
    "digest": "摘要（≤120字，留空抓正文前54字）",
    "content": "<p>HTML 正文…</p>",
    "content_source_url": "https://... 阅读原文",
    "thumb_media_id": "永久素材封面 media_id（news 类型必填）",
    "need_open_comment": 0,
    "only_fans_can_comment": 0
  }]
}
```

### 步骤 5 状态与事件

- `publish_status`：0 成功 / 1 发布中 / 2 原创失败 / 3 常规失败 / 4 平台审核不通过 / 5 用户删除 / 6 系统封禁
- 成功时 `article_detail.item[0].article_url` 即 `https://mp.weixin.qq.com/s/...` 永久链接
- 也可订阅回调事件 `PUBLISHJOBFINISH`（`publish_id`、`publish_status`、`article_id`、`article_url`、`fail_idx`）

## 分类来源与要点

### 官方文档（首选）

| 来源 | 关键信息 |
|---|---|
| [新增草稿 draft/add](https://developers.weixin.qq.com/doc/subscription/api/draftbox/draftmanage/api_draft_add) | 字段限制：标题 32 字、摘要 120 字、content 支持 HTML 且 <2 万字符/<1MB、去 JS；图片必须来自 uploadimg；`thumb_media_id` 必须是永久 MediaID |
| [发布草稿 freepublish/submit](https://developers.weixin.qq.com/doc/service/api/public/api_freepublish_submit.html) | `errcode=0` 只代表**任务提交成功**，不等于发布完成；常见错误 48001（未授权）、53503（草稿未过发布检查）、53504/53505（需后台手动操作） |
| [发布状态查询 freepublish/get](https://developers.weixin.qq.com/doc/subscription/api/public/api_freepublish_get) | 用 `publish_id` 轮询；返回 `article_detail.item[].article_url` |
| [发布能力总览](https://developers.weixin.qq.com/doc/subscription/guide/product/publish.html) | 5 个接口：batchget / delete / get / getarticle / submit。**2025 年 7 月起个人主体、企业未认证账号被回收这些接口权限** |
| [上传发表内容中的图片 uploadimg](https://developers.weixin.qq.com/doc/subscription/api/material/permanent/api_uploadimage.html) | `POST /cgi-bin/media/uploadimg`，jpg/png、<1MB，不占 10 万素材上限，返回 `mmbiz.qpic.cn` URL |
| [上传永久素材 add_material](https://developers.weixin.qq.com/doc/subscription/api/material/permanent/api_addmaterial.html) | 封面走这里（type=image，<2MB）；腾讯系域名外使用图片会被屏蔽 |
| [群发 sendall](https://developers.weixin.qq.com/doc/subscription/api/notify/message/api_sendall) | `msgtype=mpnews` + 草稿 `media_id`，`filter.is_to_all`；订阅号 1 次/天、服务号 4 次/月 |
| [MediaApiDoc.pdf](https://res.wx.qq.com/download/MediaApiDoc.pdf) | 官方 PDF 明确整体流程：上传封面 → 上传正文图 → 上传视频(可选) → 上传至发布库 → 提交发布审核 |

### 社区 / 实践

| 来源 | 关键信息 |
|---|---|
| [微信开放社区：发布 vs 群发](https://developers.weixin.qq.com/community/develop/doc/0004648a3f08a087cb3dda50c56400) | 官方答复：**发布是把素材发表到主页/看一看，不发给粉丝、不占群发次数、可多次发；群发才推送给粉丝** |
| [逻辑客栈：通过公众号 API 发表文章](https://blog.yuccn.net/archives/1259.html) | Python 四步封装（token → 封面 → 草稿 → 发布），`json.dumps(..., ensure_ascii=False)` 避免中文乱码；发布异步需轮询 |
| [开放社区：草稿样式丢失提问](https://fuwu.weixin.qq.com/community/develop/doc/00086cce4b4b6015a7f245cd66bc00) | `draft/add` 后样式可能与后台编辑不一致；排查法 = 后台取同一篇文章 content 重走接口对比 |
| [开放社区：API 发布不进主页（2026-04）](https://developers.weixin.qq.com/community/develop/doc/00044eead745d8770b051241d6b800) | 用户实测：API 发布成功链接可访问但**不一定出现在公众号主页**，后台手动发表可以；行为可能变动，需实测确认 |
| [acedatacloud skills: wechat-official-account](https://github.com/acedatacloud/skills/blob/main/skills/wechat-official-account/SKILL.md) | 完整 curl 实战 + 错误码速查：40164 IP 不在白名单、40001 token 过期、45009 日配额、48001 未授权；access_token 全局 ≈2000 次/天 |

### Elixir 生态

| 来源 | 关键信息 |
|---|---|
| [wechat_sdk (hex: `wechat`)](https://wechat-sdk.hexdocs.pm/WeChat.html) | `{:wechat, "~> 0.18", hex: :wechat_sdk}`；`use WeChat, appid:, appsecret:` 定义 client，自带 token 缓存 |
| [`WeChat.DraftBox`](https://hex.pm/packages/wechat_sdk/0.19.0/files/lib/wechat/official_account/draft_box.ex) | `DraftBox.add/2`、`get/2`、`update/4`、`batch_get/4`、`stream_get/3` |
| [`WeChat.Publish`](https://hex.pm/packages/wechat_sdk/0.20.1/files/lib/wechat/official_account/publish.ex) | `Publish.publish/2`、`get_status/2`、`delete/3`、`get_article/2`、`batch_get/4`、`stream_get/3` |

## Elixir 代码示例（wechat_sdk）

```elixir
# mix.exs
{:wechat, "~> 0.18", hex: :wechat_sdk}

defmodule MyApp.WX do
  use WeChat, appid: "wx...", appsecret: "..."
end

alias WeChat.{DraftBox, Publish}

# 1) 封面：永久素材
{:ok, %{body: %{"media_id" => cover}}} =
  MyApp.WX.material.add_material(:image, {:file, "cover.jpg"})

# 2) 草稿
{:ok, %{body: %{"media_id" => draft_id}}} =
  DraftBox.add(MyApp.WX, %{
    title: "标题",
    author: "作者",
    digest: "摘要",
    content: html_body,          # 正文图片必须用 uploadimg 返回的 URL
    thumb_media_id: cover,
    content_source_url: "https://..."
  })

# 3) 发布（异步）
{:ok, %{body: %{"publish_id" => pid}}} = Publish.publish(MyApp.WX, draft_id)

# 4) 轮询（约 5–30 秒）
case Publish.get_status(MyApp.WX, pid) do
  {:ok, %{body: %{"publish_status" => 0} = r}} ->
    get_in(r, ["article_detail", "item", Access.at(0), "article_url"])
  {:ok, %{body: %{"publish_status" => 1}}} -> :timer.sleep(3_000); retry(...)
  {:ok, %{body: %{"publish_status" => s, "fail_idx" => idx}}} -> {:error, s, idx}
end
```

裸 HTTP（不用 SDK）时注意：JSON 用 UTF-8 编码且**不要**把中文转成 `\uXXXX`（官方明说会出问题），`access_token` 走 query string。

## 建议

1. **先确认账号资质**：企业主体 + 已认证，否则 `freepublish/*` 直接 48001。个人号只能建草稿（`draft/*`），无法 API 发布。
2. **区分两个目标**：只要"发表出文章拿永久链接" → `freepublish`；要"推送给粉丝" → 之后再 `mass/sendall`，注意额度（订阅号 1/天、服务号 4/月）。
3. **图片两套接口别搞混**：封面 = `material/add_material`（拿 `media_id`）；正文内图 = `media/uploadimg`（拿 `url`）。外链图片会被过滤。
4. **异步收尾**：`submit` 返回 0 ≠ 成功，必须轮询 `freepublish/get` 或接 `PUBLISHJOBFINISH` 事件，`publish_status` ∈ {2,3,4} 时用 `fail_idx` 定位失败篇目。
5. **基础设施**：出 IP 加入公众平台 IP 白名单（40164）；`access_token` 缓存复用（TTL 7200s，全局约 2000 次/天），推荐直接用 `wechat_sdk` 省掉这层。
6. **Elixir 选型**：`wechat_sdk` 已覆盖 DraftBox/Publish/Material 全链路，优先用它；只需简单封装"建草稿 + 发布 + 轮询"三段。
7. **上线前小流量验证**：发布行为（是否进主页、审核规则）2025–2026 有变动记录，先用测试号或少量文章跑通再自动化。

## 坑与版本约束

- **权限**：2025-07 起个人主体 / 企业未认证账号回收 `freepublish/*`、`mass/*` 调用权限。
- **content 限制**：<2 万字符、<1MB、自动去 JS；标题 ≤32 字、摘要 ≤120 字；不要传 Unicode 转义。
- **`thumb_media_id` 必须永久素材**，临时素材会 40007。
- **`errcode=0` 只是提交成功**，原创声明失败、平台审核不通过在后续状态里。
- **53503/53504/53505**：草稿未过发布检查或需去公众平台后台手动操作，API 无法绕过。
- **40164**：出口 IP 不在白名单；**45009**：接口日配额用尽；**40001/42001**：token 过期需重取。
- **发布 ≠ 群发 ≠ 主页展示**：发布不推粉丝、不占群发额度；且 2026-04 社区实测 API 发布内容可能不出现在公众号主页（行为待官方确认）。
- **草稿被消费**：素材一旦群发或发布即从草稿箱移除，重发需重建草稿。

## 本机实测（2026-09-27）

复验脚本：`scripts/wx_smoke_test.sh`（只读探测，不创建/发布内容）

### appid `wxdb7558b71abf8570` = 小程序，不是公众号

| 接口 | 归属 | 结果 |
|---|---|---|
| `cgi-bin/token` | 通用 | ✅ token 正常（TTL 7200s） |
| `wxa/getwxadevinfo` | 小程序 | ✅ `errcode:0`，业务域名 `api.catspvp.com` |
| `wxa/api_create_wxa_code` | 小程序 | ✅ `40066 invalid url`（路径不存在 ≠ 无权限） |
| `cgi-bin/draft/count` | 公众号 | ❌ 48001 |
| `cgi-bin/freepublish/batchget` | 公众号 | ❌ 48001 |
| `cgi-bin/material/get_materialcount` | 公众号 | ❌ 48001 |
| `cgi-bin/user/info` | 公众号 | ❌ 48001 |

**结论**：公众号与小程序权限体系不通用，token 不能跨类型复用。小程序 appid 调公众号接口一律 48001。
（`cgi-bin/getcallbackip` 两侧都能通，它是通用接口，不能作为公众号权限的证据。）

### appid `wxbec0b59f1aa87e6c` = 公众号，卡 IP 白名单

```
{"errcode":40164,"errmsg":"invalid ip 117.129.8.8 ipv6 ::ffff:117.129.8.8, not in whitelist"}
```

- **凭证有效** —— 能走到 IP 校验这一步说明 appid/secret 都对（secret 错会返回 40125，appid 错返回 40013）
- 出口是**双栈**的，IPv4 与 IPv6 交替出现；`api.weixin.qq.com` 走 IPv4，微信看到的是 `::ffff:117.129.8.8`
- IPv4 出口 `117.129.8.8` 采样 5 次稳定，归属 AS56048 中国移动（北京）
- ⚠️ 移动网络 IP 可能是动态的，白名单固化后仍需监控；生产环境建议走固定出口（云服务器/NAT 网关）

### 权限结论

- `40164` → 加白名单即可继续（后续脚本会自动跑到权限矩阵）
- `48001` 且 token 正常 → 才是资质问题（个人主体/未认证号 2025-07 起被回收 `freepublish/*`），去「设置与开发 → 接口权限」确认勾选

## 公众号 `wxbec0b59f1aa87e6c` 权限实测（2026-09-27）

IP 白名单加入 `117.129.8.8` 后通过（生效延迟约 20~30s，脚本重试即可）。

### 权限图谱

| 接口 | 能力 | 结果 |
|---|---|---|
| `cgi-bin/token` / `stable_token` | 取 token | ✅ 7200s |
| `cgi-bin/getcallbackip` | 通用 | ✅ |
| `cgi-bin/get_current_selfmenu_info` | 自定义菜单 | ✅ `{"is_menu_open":0}` |
| `cgi-bin/draft/count` | 草稿箱 | ✅ `{"total_count":0}` |
| `cgi-bin/draft/batchget` | 草稿箱 | ✅ `{"item":[],"total_count":0}` |
| `cgi-bin/material/get_materialcount` | 素材库 | ✅ 四类计数全 0 |
| `cgi-bin/freepublish/batchget` | **发布** | ❌ 48001 |
| `cgi-bin/freepublish/get` | **发布状态** | ❌ 48001 |
| `cgi-bin/message/mass/sendall` | **群发** | ❌ 48001 |
| `cgi-bin/message/mass/preview` | **群发预览** | ❌ 48001 |
| `cgi-bin/user/info` | 用户管理 | ❌ 48001 |

### 判读：这是典型的**未认证公众号**特征

分界线非常清晰：

- **能用**：token、菜单、草稿箱、素材库 —— 未认证号的基础能力集
- **不能用**：发布、群发、群发预览、用户管理 —— 全部需要**认证**

关键佐证是 `user/info` 也被拒。用户管理接口需要认证，与 `freepublish` 被拒是同一个原因，**不是**「后台少勾了一个接口」。

### 因此可行的两条路

**路线 A：完成认证**（唯一能拿到 `freepublish/*` 的办法）
- 注意 2025-07 规则针对的是**个人主体**，即使做了个人认证也未必解锁 `freepublish/*`
- 要稳妥拿到发布权限，需要 **企业主体 + 企业认证**

**路线 B：只做草稿，人工发表**（当前权限即可跑通）
- 素材上传 → `draft/add` → 文章出现在公众号后台草稿箱
- 由人在 mp.weixin.qq.com 后台点「发表」
- 适合作为过渡方案：API 负责内容生产，人负责最后一步投放
- 代价：不是全自动，且草稿不占群发额度

## 路线 B 端到端实测通过（2026-09-27）

脚本：`scripts/wx_draft_chain.py`（可重复运行，只建草稿不发布）

```
步骤 1  material/add_material  ✅ thumb_media_id = P0HLl-...s6x1H
步骤 2  media/uploadimg        ✅ http://mmbiz.qpic.cn/sz_mmbiz_png/...?from=appmsg
步骤 3  draft/add              ✅ media_id = P0HLl-...1hg7lO
步骤 4  draft/batchget         ✅ 标题回读一致、封面 media_id 匹配、正文含 1 个 mmbiz <img>
```

**重要修正**：`media/uploadimg` 在**未认证号上也可用**。原文只说图片必须来自 `uploadimg`，
但没说它需要认证 —— 实测确认它是随草稿能力一起开放的，不必等认证就能做正文配图。

### 实测踩到的三个坑

1. **`content_source_url` 不接受 localhost** → `41039 invalid content_source_url`
   「阅读原文」必须是公网可访问的 http/https URL。本地开发时直接省略该字段。
   脚本已改为读 `WECHAT_SOURCE_URL` 环境变量，为空则不传。

2. **shell 环境变量会污染凭证配对** → `40125 invalid appsecret`
   本机 shell 里已有小程序的 `WECHAT_APP_SECRET`，而 `.env` 里是公众号的。
   加载 `.env` 时若用 `os.environ.setdefault` / `System.get_env` 语义，
   会拿到**小程序 secret 配公众号 appid**，报错还很有迷惑性（看着像 secret 填错）。
   教训：多套凭证共存时，变量名必须区分（如 `WECHAT_MP_APPID` / `WECHAT_MINI_APPID`），
   或在加载时强制覆盖。本项目当前 `.env` 只放公众号，shell 变量需清掉。

3. **`add_material` 的 `type` 是 query 参数**，不在 body 里
   `POST /cgi-bin/material/add_material?access_token=X&type=image`，
   漏掉会报 40007 之类的参数错误。

### 素材清理

重复运行脚本会累积孤儿素材（10 万上限，暂不紧张但建议清理）。
`material/del_material` 已验证可用（`{"errcode":0,"errmsg":"ok"}`）。
清理前务必比对草稿的 `thumb_media_id`，别把草稿正在引用的封面删掉。

## `draft/update` 语义实测（2026-09-27）

脚本：`scripts/wx_draft_update_test.py`（开头/结尾都重置草稿，可重复运行）

### 结论

| 验证项 | 结果 |
|---|---|
| 全量更新 title / digest / content | ✅ 生效 |
| 换封面 `thumb_media_id` | ✅ 生效 |
| 稀疏更新（只传 title） | ❌ 被拒，`40007 invalid media_id` |
| 无效 media_id | `40007 invalid media_id` |
| 越界 `index` | `40114 invalid index value` |

**好消息**：稀疏更新被服务端拒绝，所以「误传半截 articles 把草稿正文清空」这个
最担心的风险**不存在**。草稿数据是安全的。

**坏消息**：拒绝时返回的是 `40007 invalid media_id`，而 `media_id` 其实是好的。
这是**误导性错误码** —— 真实原因是 `articles` 缺必填字段。
实现时绝对不能把 40007 当成「草稿已失效」去重建草稿，否则会陷入
「重建 → 再更新 → 再 40007 → 再重建」的死循环。

### 接口返回形状不一致（易踩）

- `draft/add` 成功 → `{"media_id": "..."}`，**无** `errcode` 字段
- `draft/update` 成功 → `{"errcode": 0, "errmsg": "ok"}`

所以不能用统一的 `"errcode" in resp` 判失败，必须判「`errcode` 存在且 ≠ 0」。
已封装为 `wx_common.succeeded/1` 与 `fail_reason/1`。

## ⚠️ 微信会改写正文 HTML（对写作类应用影响最大）

脚本：`scripts/wx_content_normalize_test.py`

### 1. `<a>` 标签被**完全剥除** —— 内联链接无法发布

```
发送: ...<a href="https://example.com/p/1">A</a>...
回读: ...A...
```

6 种写法全部被剥成纯文本：普通外链、带 `target`、无 `href`、
`mmbiz.qpic.cn`（腾讯自家域名）、带内联样式的链接 —— 一个都没活下来。
锚点元素整个消失，`href` 无一保留。

**对产品的含义**：正文里的任何超链接都发不出去。唯一可用的外链通道是
`content_source_url`（阅读原文，但必须是公网 URL，localhost 会被判 41039）。
需要域名级跳转（自己的短链服务）才能在正文里放链接。

### 2. 其余规范化改写

| 发送 | 回读 |
|---|---|
| `<img src="URL" ... />` | `<img data-src="URL/640?from=appmsg" ...>` |
| `<br>` | `<br  />`（补两个空格） |
| `<img ... />` | `<img ...>`（去掉自闭合斜杠） |
| `<p style="color:#ff0000;">` | 原样保留 ✅ |
| `<h2 style="margin:0 0 10px 0;">` | 原样保留 ✅（多值样式不丢） |

注意 `src` 被改名为 `data-src` 且 URL 换成 `/640?from=appmsg` 变体 ——
若把 `draft/get` 的回读内容直接塞进自家编辑器渲染，图片会裂。

### 3. **改写不幂等** —— 读回再编辑会累积漂移

把回读内容原样再写回去，第三次回读又变了（`+3` 字符）。
所以「`draft/get` → 改一处 → 整篇 `draft/update`」的循环会逐步侵蚀 HTML。
实现时应尽量避免无意义的往返写，或以本地为唯一真源、只在明确保存时提交一次。

## 草稿无法通过 API 删除

`draft/*` 只有 `add` / `get` / `update` / `count` / `batchget`，**没有 delete**。
（`freepublish/*` 有 `delete`，但那是删除已发布文章，不是草稿。）

**运维含义**：草稿会只增不减，测试/误建的草稿只能在
mp.weixin.qq.com → 草稿箱 人工删除。因此：
- 每次写实现前先跑 `scripts/wx_smoke_test.sh` 确认权限
- 用完跑 `scripts/wx_cleanup.py --dry-run` 看残留，别反复建草稿

⚠️ `wx_cleanup.py` 删素材时必须扫描**所有**草稿的 `thumb_media_id`，
只查要保留的那一篇会误删其他草稿的封面，导致后台显示破图（本次已踩过）。




