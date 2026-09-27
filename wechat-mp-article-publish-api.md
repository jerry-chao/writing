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
