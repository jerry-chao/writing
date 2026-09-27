#!/usr/bin/env python3
"""验证 draft/update 语义。

回答四个实现层面的问题:
  A. 全量更新能否生效 (标题/摘要/正文)
  B. 部分更新(只传 title)会不会把其他字段清空 -> 决定要不要防呆
  C. 封面能否在更新时替换 (thumb_media_id)
  D. 错误码: 无效 media_id / 越界 index

脚本开头与结尾都会把草稿重置为规范状态, 因此可安全重复运行。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wx_common import (TMP, post_json, add_cover_image, del_material, latest_draft,
                       material_count, ok, warn, die, token, succeeded, fail_reason)
from wx_draft_chain import reset_draft, build_content, build_article

MARK = "update-新增段落-7f3a2b"
EXTRA = ('<p style="margin-top:16px;padding:10px 12px;background:#eef4fb;border-radius:6px;'
         f'color:#2b5c8a;">⬆️ {MARK}</p>')


def make_cover_v2(path):
    from PIL import Image, ImageDraw, ImageFont
    cjk = "/System/Library/Fonts/Supplemental/Songti.ttc"
    img = Image.new("RGB", (900, 383), (56, 30, 34))
    d = ImageDraw.Draw(img)
    for y in range(383):
        t = y / 382
        d.line([(0, y), (900, y)], fill=(int(56 + 40 * t), int(30 + 22 * t), int(34 + 30 * t)))
    d.rectangle([40, 40, 44, 343], fill=(255, 138, 128))
    d.text((70, 118), "封面 v2 · 已替换", font=ImageFont.truetype(cjk, 46), fill=(255, 255, 255))
    d.text((72, 190), "draft/update 换图验证",
           font=ImageFont.truetype(cjk, 24, 1), fill=(240, 190, 186))
    d.text((72, 288), "2026-09-27  ·  更新测试",
           font=ImageFont.truetype(cjk, 18, 1), fill=(190, 140, 138))
    img.save(path, "JPEG", quality=88, optimize=True)


def brief(a):
    return {
        "title": a.get("title"),
        "author": a.get("author"),
        "digest": (a.get("digest") or "")[:26],
        "content_len": len(a.get("content", "")),
        "content_imgs": a.get("content", "").count("<img"),
        "thumb": a.get("thumb_media_id", "")[:24],
    }


def show(label, a):
    print(f"\n  {label}:")
    for k, v in brief(a).items():
        print(f"    {k:13} {v}")


def main():
    tok = token()
    tk = tok["access_token"]
    ok(f"token ok (TTL {tok['expires_in']}s)")

    print("\n== 0. 重置为规范状态 ==")
    draft_id, old_thumb, inline_url = reset_draft(tk)
    _, base = latest_draft(tk)
    ok(f"草稿 {draft_id[:28]}...")
    show("规范状态", base)
    assert base["content"].count("<img") == 1, "重置后应含 1 张内嵌图"

    # ---------- D. 错误码 ----------
    print("\n== D. 错误码行为 ==")
    r = post_json("/cgi-bin/draft/update", tk,
                  {"media_id": "P0HLl-FAKE_not_real", "index": 0, "articles": build_article(old_thumb, build_content())})
    warn(f"  无效 media_id  -> {fail_reason(r)}")
    r = post_json("/cgi-bin/draft/update", tk,
                  {"media_id": draft_id, "index": 99, "articles": build_article(old_thumb, build_content())})
    warn(f"  越界 index=99  -> {fail_reason(r)}")

    # ---------- A + C. 全量更新 + 换封面 ----------
    print("\n== A+C. 全量更新 (含换封面) ==")
    make_cover_v2(f"{TMP}/cover_v2.jpg")
    cover_v2 = add_cover_image(f"{TMP}/cover_v2.jpg", tk)
    ok(f"v2 封面 media_id = {cover_v2[:24]}...")

    updated = build_article(cover_v2, build_content(inline_url) + EXTRA)
    updated["title"] = "写作 · 草稿更新验证"
    updated["digest"] = "验证 draft/update 是全量覆盖还是部分覆盖, 以及封面能否替换。"

    r = post_json("/cgi-bin/draft/update", tk,
                  {"media_id": draft_id, "index": 0, "articles": updated})
    if not succeeded(r):
        die(f"全量更新失败: {fail_reason(r)}")
    ok(f"draft/update 返回 {fail_reason(r)}")

    _, after = latest_draft(tk)
    show("更新后回读", after)
    print()
    for k, v in {
        "标题已更新":     after.get("title") == updated["title"],
        "摘要已更新":     after.get("digest") == updated["digest"],
        "新增段落已写入": MARK in after.get("content", ""),
        "封面已替换":     after.get("thumb_media_id") == cover_v2,
        "正文长度已变":   len(after.get("content", "")) == len(updated["content"]),
    }.items():
        print(f"  {'✅' if v else '❌'} {k}")

    # ---------- B. 稀疏更新是否清空 ----------
    print("\n== B. 稀疏更新 (只传 title) 是否清空其他字段 ==")
    r = post_json("/cgi-bin/draft/update", tk,
                  {"media_id": draft_id, "index": 0, "articles": {"title": "只有标题的更新"}})
    if not succeeded(r):
        warn(f"  接口拒绝稀疏更新: {fail_reason(r)}")
    _, s = latest_draft(tk)
    if s.get("title") == "只有标题的更新":
        wiped = {
            "摘要 digest":  not s.get("digest"),
            "正文 content": not s.get("content"),
            "封面 thumb":   not s.get("thumb_media_id"),
        }
        for k, gone in wiped.items():
            print(f"  {'❌ 被清空' if gone else '✅ 保留'}  {k:12} -> {str(brief(s).get(k))[:40]}")
        print("\n  判定: " + (
            "🚨 draft/update 是全量覆盖 —— 只传 title 会清空摘要/正文/封面。\n"
            "     实现时必须先 draft/get 读回完整 article, 改字段后整篇提交。\n"
            "     切勿把用户表单直接当 articles 发出去。"
            if any(wiped.values()) else
            "✅ 接口为部分合并语义, 可安全只提交要改的字段。"))
    else:
        warn(f"  标题未变更 (仍为 {s.get('title')!r}) — 稀疏更新被服务端忽略/拒绝")

    # ---------- 还原 + 清理 ----------
    print("\n== 还原 + 清理 ==")
    reset_draft(tk, draft_id)
    ok("草稿已重置为规范状态")
    for mid, label in ((cover_v2, "v2 封面"), (old_thumb, "被替换的旧封面")):
        r = del_material(mid, tk)
        ok(f"{label}已清理" if succeeded(r) else f"{label}清理: {fail_reason(r)}")

    _, fin = latest_draft(tk)
    show("还原后回读", fin)
    mat = material_count(tk)
    ok(f"\n  素材库剩余图片: {mat.get('image_count')} 张 · 草稿箱 {post_json('/cgi-bin/draft/count', tk, {}).get('total_count')} 篇")


if __name__ == "__main__":
    main()
