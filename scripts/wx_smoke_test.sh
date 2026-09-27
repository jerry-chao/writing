#!/usr/bin/env bash
# 公众号 API 可行性冒烟测试
#
# 用法:  ./scripts/wx_smoke_test.sh
#
# 覆盖研究文档里的关键约束:
#   1. access_token 能否获取            -> 凭证有效性
#   2. freepublish/* 是否有权限         -> 2025-07 起需企业主体已认证
#   3. draft/* 是否有权限
#   4. material/* 是否有权限            -> 封面图上传前提
#   5. 出口 IP 是否需要加白名单
#
# 只做只读探测，不创建/发布任何内容。

set -uo pipefail

ENV_FILE="${ENV_FILE:-.env}"
API="https://api.weixin.qq.com"

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

# 兼容 .env 里的 WECHAt_APP_SECRET 大小写笔误
APPID="${WECHAT_APPID:-}"
SECRET="${WECHAT_APP_SECRET:-${WECHAt_APP_SECRET:-}}"

die() { printf '\033[31m%s\033[0m\n' "$*"; exit 1; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }
warn(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ -n "$APPID" ]   || die "缺少 WECHAT_APPID  (来源: $ENV_FILE)"
[ -n "$SECRET" ]  || die "缺少 WECHAT_APP_SECRET (来源: $ENV_FILE)"

echo "appid: $APPID"
echo "出口 IPv4: $(curl -4 -s --max-time 8 https://ifconfig.co/ip)"
echo

# ---------- 1. access_token ----------
echo "== 1. access_token =="
TOKEN_JSON=$(curl -s --max-time 15 -G "$API/cgi-bin/token" \
  --data-urlencode "grant_type=client_credential" \
  --data-urlencode "appid=$APPID" \
  --data-urlencode "secret=$SECRET")

TOKEN=$(printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "$TOKEN_JSON"
  echo
  case "$TOKEN_JSON" in
    *40164*) die "❌ IP 不在白名单。到 mp.weixin.qq.com → 设置与开发 → 基本配置 → IP白名单
         加上上面那个出口 IPv4 地址。" ;;
    *40001*|*42001*) die "❌ token 无效/过期（若刚换过 secret，等 5 分钟再试）" ;;
    *40125*) die "❌ appsecret 错误" ;;
    *40013*) die "❌ appid 错误" ;;
    *) die "❌ 取 token 失败（见上方原始响应）" ;;
  esac
fi

ok "✅ token 获取成功 (TTL $(printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("expires_in","?"))')s)"

# ---------- 2. 权限矩阵 ----------
# 48001 = 该账号无此接口权限(未认证/个人主体/未在后台开通)
probe() {
  local label="$1" method="$2" path="$3" body="${4:-}"
  local resp
  if [ "$method" = "GET" ]; then
    resp=$(curl -s --max-time 15 "$API$path?access_token=$TOKEN")
  else
    resp=$(curl -s --max-time 15 -X POST "$API$path?access_token=$TOKEN" \
      -H "Content-Type: application/json" -d "$body")
  fi
  if printf '%s' "$resp" | grep -q '"errcode":48001'; then
    warn "❌ $label -> 48001 api unauthorized"
  elif printf '%s' "$resp" | grep -qE '"errcode":(4|5)[0-9]{4}'; then
    warn "⚠️  $label -> $(printf '%s' "$resp" | head -c 160)  (接口已授权, 参数/配额问题)"
  else
    ok "✅ $label -> $(printf '%s' "$resp" | head -c 160)"
  fi
}

echo
echo "== 2. 发布链路权限矩阵（全部只读）=="
probe "freepublish/batchget  " POST "/cgi-bin/freepublish/batchget" '{"offset":0,"count":1,"no_content":1}'
probe "draft/count          " GET  "/cgi-bin/draft/count"
probe "material/count       " GET  "/cgi-bin/material/get_materialcount"
probe "getcallbackip        " GET  "/cgi-bin/getcallbackip"

echo
echo "== 3. 素材库现状（决定是否需先清理额度）=="
curl -s --max-time 15 "$API/cgi-bin/material/get_materialcount?access_token=$TOKEN" \
  | python3 -m json.tool 2>/dev/null || echo "(不可用)"

echo
echo "== 结论 =="
FREEP=$(curl -s --max-time 15 -X POST "$API/cgi-bin/freepublish/batchget?access_token=$TOKEN" \
  -H "Content-Type: application/json" -d '{"offset":0,"count":1,"no_content":1}')
DRAFT=$(curl -s --max-time 15 "$API/cgi-bin/draft/count?access_token=$TOKEN")

if printf '%s' "$FREEP" | grep -q '48001' || printf '%s' "$DRAFT" | grep -q '48001'; then
  warn "❌ 发布链路未打通。研究文档的四步流程目前跑不通。"
  echo "   可能原因（按研究文档）："
  echo "     a) 公众号为企业主体且已认证 —— 个人主体/未认证号 2025-07 起被回收 freepublish/*"
  echo "     b) 公众平台后台「开发接口管理」里未勾选对应接口"
  echo "   排查入口: mp.weixin.qq.com → 设置与开发 → 接口权限"
else
  ok "✅ 发布链路已打通，可以继续验证：上传封面 → draft/add → freepublish/submit"
fi
