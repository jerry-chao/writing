#!/usr/bin/env python3
"""微信公众号 API 共享工具。

被 wx_draft_chain.py / wx_draft_update_test.py 复用。
只放函数, 不含顶层副作用, 可安全 import。
"""
import json
import os
import sys
import mimetypes
import uuid
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.weixin.qq.com"
TMP = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.environ.get("ENV_FILE", ".env")


def load_env(path=None):
    """让 .env 覆盖已存在的环境变量。

    不能用 setdefault。shell 里常已存在同名变量(例如另一套 appid 的
    WECHAT_APP_SECRET), setdefault 会保留旧值, 导致 appid/secret 配对错乱,
    表现为 40125 invalid appsecret。
    """
    for line in open(path or ENV_FILE, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip()
            if os.environ.get(k) != v:
                print(f"  (env 覆盖) {k}: {os.environ.get(k, '<unset>')} -> {'*' * 8}{v[-4:]}")
            os.environ[k] = v


def ok(msg):
    print(f"\033[32m{msg}\033[0m")


def warn(msg):
    print(f"\033[33m{msg}\033[0m")


def die(msg):
    print(f"\033[31m{msg}\033[0m")
    sys.exit(1)


def _request(req, timeout=30):
    """统一处理 HTTP 层错误, 把微信返回的 errcode/errmsg 带出来。"""
    try:
        return json.loads(urllib.request.urlopen(req, timeout=timeout).read())
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"errcode": e.code, "errmsg": raw[:300]}


def token(force_refresh=False):
    """取 access_token。优先 stable_token(微信侧有独立的 token 版本管理)。"""
    load_env()
    appid, secret = os.environ["WECHAT_APPID"], os.environ["WECHAT_APP_SECRET"]
    body = json.dumps({
        "grant_type": "client_credential", "appid": appid, "secret": secret,
        "force_refresh": force_refresh,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{API}/cgi-bin/stable_token", data=body,
        headers={"Content-Type": "application/json"})
    r = _request(req)
    if "access_token" not in r:
        die(f"取 token 失败: {r}")
    return r


def post_json(path, token, payload):
    """注意: ensure_ascii=False —— 中文转成 \\uXXXX 会被微信判异常。"""
    url = f"{API}{path}?access_token={token}"
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json; charset=utf-8"})
    return _request(req)


def upload_file(api_path, file_path, token, field="media", filename=None, mime=None, params=None):
    """multipart/form-data 上传。api_path 与 file_path 必须分开传。"""
    query = {"access_token": token, **(params or {})}
    url = f"{API}{api_path}?" + urllib.parse.urlencode(query)
    boundary = "----WebKitFormBoundary" + uuid.uuid4().hex[:16]
    filename = filename or os.path.basename(file_path)
    mime = mime or mimetypes.guess_type(file_path)[0] or "application/octet-stream"

    with open(file_path, "rb") as fh:
        blob = fh.read()

    parts = [
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'.encode(),
        f"Content-Type: {mime}\r\n\r\n".encode(),
        blob,
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    req = urllib.request.Request(
        url, data=b"".join(parts), method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    return _request(req, timeout=60)


def add_cover_image(file_path, token):
    """上传封面到永久素材库, 返回 media_id。"""
    r = upload_file("/cgi-bin/material/add_material", file_path, token, params={"type": "image"})
    if "media_id" not in r:
        die(f"封面素材上传失败: {r}")
    return r["media_id"]


def upload_inline_image(file_path, token):
    """上传正文内嵌图, 返回 mmbiz.qpic.cn 的 URL。失败返回 None。"""
    r = upload_file("/cgi-bin/media/uploadimg", file_path, token)
    if "url" in r:
        return r["url"]
    warn(f"uploadimg 不可用 ({r.get('errcode')}) — 正文将退化为纯文字")
    return None


def del_material(media_id, token):
    return post_json("/cgi-bin/material/del_material", token, {"media_id": media_id})


def succeeded(r):
    """判断微信接口是否成功。

    ⚠️ 各接口的成功返回形状不一致, 不能统一用 `"errcode" in r` 判断:
      - draft/add          成功 -> {"media_id": "..."}          (无 errcode 字段)
      - draft/update       成功 -> {"errcode": 0, "errmsg": "ok"}  (带 errcode=0)
    所以必须判断「errcode 存在且不为 0」才算失败。
    """
    return "errcode" not in r or r.get("errcode") == 0


def fail_reason(r):
    """把失败响应压成一行可读文本。"""
    if succeeded(r):
        return "ok"
    return f"{r.get('errcode')}  {r.get('errmsg', '')[:70]}"


def material_count(token):
    r = _request(urllib.request.Request(
        f"{API}/cgi-bin/material/get_materialcount?access_token={token}"))
    return r


def draft_count(token):
    return post_json("/cgi-bin/draft/count", token, {})


def latest_draft(token):
    """返回最近一篇草稿的 (media_id, article)。草稿箱为空时返回 (None, None)。"""
    lst = post_json("/cgi-bin/draft/batchget", token, {"offset": 0, "count": 1})
    if not lst.get("item"):
        return None, None
    media_id = lst["item"][0]["media_id"]
    got = post_json("/cgi-bin/draft/get", token, {"media_id": media_id})
    if "news_item" not in got:
        return media_id, None
    return media_id, got["news_item"][0]
