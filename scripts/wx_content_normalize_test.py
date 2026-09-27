#!/usr/bin/env python3
"""探查 draft/update 对 content HTML 的改写行为。

为什么重要: 若微信会规范化 HTML, 那么「读回草稿 -> 改一处 -> 整篇回写」的循环
会导致内容逐步漂移(属性顺序、样式被剥除、标签闭合方式变化等)。
"""
import difflib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wx_common import post_json, latest_draft, ok, warn, die, token, succeeded, fail_reason
from wx_draft_chain import reset_draft, build_content, build_article

PROBE = ('<section style="font-size:16px;">'
         '<p>普通段落</p>'
         '<p style="color:#ff0000;">带内联样式</p>'
         '<blockquote style="border-left:3px solid #000;">无 padding 声明</blockquote>'
         '<ul><li>无 style 的列表</li></ul>'
         '<img src="INLINE_URL" style="max-width:100%;" />'
         '<a href="https://example.com" class="x" id="y">属性顺序测试</a>'
         '<table border="1"><tr><td>表格</td></tr></table>'
         '<h2 style="margin:0 0 10px 0;">多个值样式</h2>'
         '<p>未闭合标签<br>换行</p>'
         '</section>')

tok = token()
tk = tok["access_token"]
ok(f"token ok (TTL {tok['expires_in']}s)")

draft_id, thumb, inline_url = reset_draft(tk)
sent = PROBE.replace("INLINE_URL", inline_url)
article = build_article(thumb, sent)
r = post_json("/cgi-bin/draft/update", tk,
              {"media_id": draft_id, "index": 0, "articles": article})
if not succeeded(r):
    die(f"update 失败: {fail_reason(r)}")

_, got = latest_draft(tk)
back = got["content"]

ok("已写入探针内容, 开始比对回读结果")
print(f"\n  发送长度: {len(sent)}   回读长度: {len(back)}   差值: {len(back) - len(sent):+d}")
print(f"  逐字符相等: {'✅ 是' if back == sent else '❌ 否'}")

if back != sent:
    print("\n  差异 (发送 -> 回读):")
    sm = difflib.SequenceMatcher(None, sent, back)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        a, b = sent[i1:i2], back[j1:j2]
        print(f"    [{tag}]")
        if a:
            print(f"       发送: {a[:150]!r}")
        if b:
            print(f"       回读: {b[:150]!r}")

    # 判断漂移是否会累积: 把回读内容再写回去, 看是否稳定
    print("\n== 幂等性测试: 用回读内容再写一次, 看是否收敛 ==")
    article2 = dict(article)
    article2["content"] = back
    post_json("/cgi-bin/draft/update", tk,
              {"media_id": draft_id, "index": 0, "articles": article2})
    _, got2 = latest_draft(tk)
    back2 = got2["content"]
    if back2 == back:
        ok("✅ 回读内容已稳定 —— 首次规范化后不再漂移, 读回编辑是安全的")
    else:
        warn(f"⚠️  仍在漂移 (第 2 次回读长度 {len(back2)}, 又变了 {len(back2)-len(back):+d})")
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, back, back2).get_opcodes():
            if tag != "equal":
                print(f"    [{tag}]  {back[i1:i2][:90]!r} -> {back2[j1:j2][:90]!r}")

print(f"\n  最终草稿 {draft_id}")
