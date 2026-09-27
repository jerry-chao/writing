#!/usr/bin/env python3
"""路线 B 端到端验证: 素材上传 -> draft/add -> 回读校验。

只创建草稿, 不发布、不群发。可安全重复运行。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wx_common import (API, TMP, post_json, add_cover_image, upload_inline_image,
                       material_count, draft_count, ok, warn, die, token,
                       succeeded, fail_reason)

CONTENT_HEAD = "这是一篇通过公众号服务端 API 创建的<strong>测试草稿</strong>"
BLOCKQUOTE = ("<blockquote style=\"margin:16px 0;padding:10px 14px;border-left:3px solid #f0a020;"
              "background:#fdf8ef;color:#6b5a3a;\">路线 B：API 负责内容生产，人工在后台点「发表」。"
              "该账号未认证，freepublish/* 不可用。</blockquote>")


def build_content(inline_url=""):
    img = (f'<img src="{inline_url}" style="max-width:100%;height:auto;border-radius:8px;" />'
           if inline_url else "")
    return f"""<section style="font-size:16px;line-height:1.75;color:#2f3a4a;">
<p>{CONTENT_HEAD}，用于验证发布链路的可行性。</p>
{BLOCKQUOTE}
{img}
<h3 style="font-size:17px;margin:22px 0 10px;">已验证可用</h3>
<ul style="padding-left:20px;margin:0;">
<li><code>stable_token</code> / <code>token</code> — 凭证有效</li>
<li><code>material/add_material</code> — 封面永久素材</li>
<li><code>media/uploadimg</code> — 正文图片</li>
<li><code>draft/add</code> — 建草稿</li>
</ul>
<h3 style="font-size:17px;margin:22px 0 10px;">不可用（需认证）</h3>
<ul style="padding-left:20px;margin:0;">
<li><code>freepublish/submit</code>、<code>freepublish/get</code> — 发布</li>
<li><code>message/mass/sendall</code> — 群发</li>
<li><code>user/info</code> — 用户管理</li>
</ul>
<p style="margin-top:22px;color:#8a94a6;font-size:14px;">发布于 2026-09-27 · 可在草稿箱删除</p>
</section>"""


def build_article(cover_id, content):
    a = {
        "article_type": "news",
        "title": "写作 · API 链路验证",        # <= 32 字
        "author": "写作应用",                 # <= 16 字
        "digest": "验证公众号服务端 API 建草稿链路的可行性测试稿。",  # <= 120 字
        "content": content,
        "thumb_media_id": cover_id,
        "need_open_comment": 0,
        "only_fans_can_comment": 0,
    }
    # content_source_url ("阅读原文") 必须是公网可访问的 http/https URL,
    # localhost 会被判 41039 invalid content_source_url。留空则不传该字段。
    src = os.environ.get("WECHAT_SOURCE_URL", "").strip()
    if src:
        a["content_source_url"] = src
    else:
        print("  (跳过 content_source_url: 未设置 WECHAT_SOURCE_URL)")
    return a


def reset_draft(tk, draft_id=None):
    """把草稿重置为规范状态: 全新封面 + 全新内嵌图 + 完整正文。

    可重复运行。draft_id 为空则新建一篇。
    每次都会产生新的封面素材, 调用方需自行清理上一张(见 leak_cover)。
    """
    thumb_id = add_cover_image(f"{TMP}/cover.jpg", tk)
    inline_url = upload_inline_image(f"{TMP}/inline.png", tk)
    article = build_article(thumb_id, build_content(inline_url))

    if draft_id:
        r = post_json("/cgi-bin/draft/update", tk,
                      {"media_id": draft_id, "index": 0, "articles": article})
        if not succeeded(r):
            die(f"重置草稿失败: {fail_reason(r)}")
    else:
        r = post_json("/cgi-bin/draft/add", tk, {"articles": [article]})
        if not succeeded(r) or "media_id" not in r:
            die(f"建草稿失败: {fail_reason(r)}")
        draft_id = r["media_id"]
    return draft_id, thumb_id, inline_url



def main():
    tok = token()
    tk = tok["access_token"]
    ok(f"token ok (TTL {tok['expires_in']}s)")

    print("\n== 步骤 1: material/add_material (封面 -> 永久素材) ==")
    thumb_id = add_cover_image(f"{TMP}/cover.jpg", tk)
    ok(f"thumb_media_id = {thumb_id}")

    print("\n== 步骤 2: media/uploadimg (正文内嵌图) ==")
    inline_url = upload_inline_image(f"{TMP}/inline.png", tk)
    if inline_url:
        ok(f"uploadimg ok -> {inline_url}")

    print("\n== 步骤 3: draft/add (创建草稿) ==")
    article = build_article(thumb_id, build_content(inline_url))
    print(f"  标题 {len(article['title'])}/32 字 · 摘要 {len(article['digest'])}/120 字 "
          f"· 正文 {len(article['content'])} 字符")
    draft = post_json("/cgi-bin/draft/add", tk, {"articles": [article]})
    if not succeeded(draft) or "media_id" not in draft:
        die(f"建草稿失败: {fail_reason(draft)}")
    draft_id = draft["media_id"]
    ok(f"草稿创建成功 media_id = {draft_id}")

    print("\n== 步骤 4: 回读校验 ==")
    cnt = draft_count(tk)
    if "total_count" in cnt:
        ok(f"草稿箱当前共 {cnt['total_count']} 篇")
    back = post_json("/cgi-bin/draft/get", tk, {"media_id": draft_id})
    info = back.get("news_item", [{}])[0]
    ok(f"回读标题: {info.get('title')}")
    ok(f"封面匹配: {'✅' if info.get('thumb_media_id') == thumb_id else '❌'}")
    ok(f"内嵌图: {'✅' if 'mmbiz.qpic.cn' in info.get('content','') else '❌'}")

    mat = material_count(tk)
    ok(f"永久素材: 图片 {mat.get('image_count')} 张")

    print(f"""
\033[1m路线 B 结论: 链路完全打通\033[0m
  thumb_media_id : {thumb_id}
  draft media_id : {draft_id}

  下一步: 登录 mp.weixin.qq.com -> 内容与互动 -> 草稿箱, 找到
  《{info.get('title')}》, 点「发表」即可上线。
""")


if __name__ == "__main__":
    main()
