#!/usr/bin/env python3
"""清理验证过程产生的草稿与孤儿素材。

保留: 第一篇草稿(最早创建的那篇), 并把它重置为规范状态。
删除: 其余测试草稿 + 所有未被保留草稿引用的素材。

用法:
  python3 scripts/wx_cleanup.py            # 清理并重置
  python3 scripts/wx_cleanup.py --dry-run  # 只列不删
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wx_common import (post_json, del_material, ok, warn, die, token,
                       succeeded, fail_reason)
from wx_draft_chain import reset_draft

DRY = "--dry-run" in sys.argv


def main():
    tok = token()
    tk = tok["access_token"]
    ok(f"token ok (TTL {tok['expires_in']}s)")

    # 列出全部草稿(offset 从 0 递增, 一次最多 20)
    print("\n== 现有草稿 ==")
    drafts = []
    offset = 0
    while True:
        r = post_json("/cgi-bin/draft/batchget", tk,
                      {"offset": offset, "count": 20, "no_content": 1})
        items = r.get("item", [])
        if not items:
            break
        drafts.extend(items)
        if len(items) < 20:
            break
        offset += 20
    for d in drafts:
        n = (d.get("content", {}).get("news_item") or [{}])[0]
        print(f"  {d['media_id'][:28]}...  {d.get('update_time')}  {n.get('title')}")
    if not drafts:
        warn("草稿箱为空")
        return

    keep = drafts[0]["media_id"]
    print(f"\n  保留: {keep[:28]}...")

    # 保留草稿重置为规范状态(会产生一张新封面)
    print("\n== 重置保留草稿 ==")
    if DRY:
        warn("dry-run: 跳过重置")
        new_thumb = None
    else:
        _, new_thumb, _ = reset_draft(tk, keep)
        ok(f"已重置, 新封面 {new_thumb[:24]}...")

    # 草稿无法通过 API 删除
    print("\n== 多余草稿 ==")
    print("  ⚠️  微信未开放草稿删除接口 (draft/* 只有 add/get/update/count/batchget),")
    print("      只能人工在 mp.weixin.qq.com -> 草稿箱 删除。以下为需人工清理的草稿:")
    for d in drafts[1:]:
        n = (d.get("content", {}).get("news_item") or [{}])[0]
        print(f"    {d['media_id'][:28]}...  {n.get('title')}")

    # 清理素材: 保留草稿引用的封面, 其余删除
    # ⚠️ 必须扫描**所有**草稿的 thumb_media_id 再删素材。之前只查了保留的那一篇,
    #    把待人工删除草稿引用的封面也删了, 导致那些草稿在后台显示破图。
    print("\n== 清理素材 ==")
    used = set()
    for d in drafts:
        r = post_json("/cgi-bin/draft/get", tk, {"media_id": d["media_id"]})
        for n in r.get("news_item", []):
            if n.get("thumb_media_id"):
                used.add(n["thumb_media_id"])
    print(f"  被 {len(drafts)} 篇草稿引用: {len(used)} 张")

    mats = []
    offset = 0
    while True:
        r = post_json("/cgi-bin/material/batchget_material", tk,
                      {"type": "image", "offset": offset, "count": 20})
        items = r.get("item", [])
        if not items:
            break
        mats.extend(items)
        if len(items) < 20:
            break
        offset += 20

    freed = 0
    for m in mats:
        mid = m["media_id"]
        if mid in used:
            print(f"  保留 {mid[:28]}...")
            continue
        if DRY:
            print(f"  would delete {mid[:28]}...")
        else:
            r = del_material(mid, tk)
            if succeeded(r):
                freed += 1
                print(f"  删除 {mid[:28]}...  ✅")
            else:
                warn(f"  删除 {mid[:28]}...  {fail_reason(r)}")
    ok(f"释放素材 {freed} 张 (共扫描 {len(mats)} 张)")


if __name__ == "__main__":
    main()
