#!/usr/bin/env bash
# ==============================================================================
#  verify-split.sh —— 验证 NAS 代理的"分流"是否真的生效
#
#  用法：
#    ./verify-split.sh                # 默认测 127.0.0.1（在 NAS 本机跑）
#    ./verify-split.sh 192.168.1.10   # 在局域网其它机器上跑
#
#  判定逻辑：
#    国内站点(ip.3322.net) 的出口 IP == 本机直连出口 IP  → 走了直连（正确）
#    国内站点 的出口 IP     != 本机直连出口 IP            → 被绕去节点了（错）
#
#  依赖：bash + curl
# ==============================================================================
set -u

HOST="${1:-127.0.0.1}"

c_ok()   { printf '\033[32m%s\033[0m' "$1"; }
c_bad()  { printf '\033[31m%s\033[0m' "$1"; }
c_warn() { printf '\033[33m%s\033[0m' "$1"; }

# 本机直连出口（国内站点视角）
DIRECT_CN=$(curl -s -m 8 --noproxy '*' http://ip.3322.net 2>/dev/null | tr -d '\r\n ')
echo "本机直连国内出口 IP : ${DIRECT_CN:-<取不到>}"
echo

printf '%-26s %-17s %-17s %-8s %s\n' "代理" "国内出口" "海外出口" "google" "分流判定"
printf '%-26s %-17s %-17s %-8s %s\n' "--------------------------" "-----------------" "-----------------" "--------" "--------"

check() {
  local label="$1" px="$2"
  local dom ovs g code verdict

  dom=$(curl -s -m 10 -x "$px" http://ip.3322.net 2>/dev/null | tr -d '\r\n ')
  ovs=$(curl -s -m 14 -x "$px" https://ipinfo.io/ip 2>/dev/null | tr -d '\r\n ')
  code=$(curl -s -m 14 -x "$px" -o /dev/null -w '%{http_code}' https://www.google.com 2>/dev/null)

  if [ -z "$dom" ]; then
    printf '%-26s %-17s %-17s %-8s %s\n' "$label" "-" "-" "${code:--}" "$(c_bad '不通')"
    return
  fi

  if [ "$dom" = "$DIRECT_CN" ]; then
    verdict=$(c_ok '✅ 国内直连')
  elif [ "$dom" = "$ovs" ]; then
    verdict=$(c_bad '❌ 全量绕出')
  else
    verdict=$(c_warn '⚠️ 未知')
  fi

  printf '%-26s %-17s %-17s %-8s %s\n' "$label" "$dom" "${ovs:--}" "${code:--}" "$verdict"
}

check "HTTP  $HOST:8118"  "http://$HOST:8118"
check "SOCKS $HOST:1080"  "socks5h://$HOST:1080"
check "HTTP  $HOST:8119"  "http://$HOST:8119"    # 全量端口，作为对照组
echo
echo "说明：8118 / 1080 应为「国内直连」；8119 是刻意的全量端口，显示「全量绕出」是对的。"
