#!/usr/bin/env bash
# ==============================================================================
#  verify-split.sh —— 验证 NAS 代理的「分流」是否真的生效
#
#  用法：
#    ./verify-split.sh                # 默认测 127.0.0.1（在 NAS 本机跑）
#    ./verify-split.sh 192.168.1.10   # 在局域网其它机器上跑
#
#  判定逻辑（不依赖本机是否已经挂了代理）：
#    8119 是全量端口，它的国内出口 = 节点 IP，拿它当「绕出去」的基准。
#    8118 / 1080 的国内出口 == 这个基准  → 也被绕出去了（错）
#    8118 / 1080 的国内出口 != 这个基准  → 国内直连（对）
#
#  依赖：bash + curl
# ==============================================================================
set -u

HOST="${1:-127.0.0.1}"

c_ok()   { printf '\033[32m%s\033[0m' "$1"; }
c_bad()  { printf '\033[31m%s\033[0m' "$1"; }
c_warn() { printf '\033[33m%s\033[0m' "$1"; }

clean() { tr -d '\r\n ' 2>/dev/null; }

# 本机视角的直连出口（只作参考：本机若已挂代理，这个值不代表家宽 IP）
DIRECT_CN=$(curl -s -m 8 --noproxy '*' http://ip.3322.net 2>/dev/null | clean)
echo "本机直连国内出口 IP : ${DIRECT_CN:-<取不到>}  (仅供参考)"

# 全量端口的国内出口 = 节点 IP，作为「被绕出去」的基准
PROXY_CN=$(curl -s -m 10 -x "http://$HOST:8119" http://ip.3322.net 2>/dev/null | clean)
echo "全量端口(8119)国内出口: ${PROXY_CN:-<取不到，判定将退化为对比本机直连>}"
echo

# 表头按「显示宽度」手写，printf 按字节算会让中文列错位
echo "代理                       国内出口          海外出口          google   分流判定"
echo "-------------------------- ----------------- ----------------- -------- --------"

check() {
  local label="$1" px="$2"
  local dom ovs code verdict

  dom=$(curl -s -m 10 -x "$px" http://ip.3322.net 2>/dev/null | clean)
  ovs=$(curl -s -m 14 -x "$px" https://ipinfo.io/ip 2>/dev/null | clean)
  code=$(curl -s -m 14 -x "$px" -o /dev/null -w '%{http_code}' https://www.google.com 2>/dev/null)

  if [ -z "$dom" ]; then
    printf '%-26s %-17s %-17s %-8s %s\n' "$label" "-" "-" "${code:--}" "$(c_bad '不通')"
    return
  fi

  if [ -n "$PROXY_CN" ] && [ "$dom" = "$PROXY_CN" ]; then
    verdict=$(c_bad '全量绕出')
  elif [ -n "$DIRECT_CN" ] && [ "$dom" = "$DIRECT_CN" ]; then
    verdict=$(c_ok '国内直连')
  elif [ -n "$PROXY_CN" ]; then
    verdict=$(c_ok '国内直连')
  else
    verdict=$(c_warn '未知')
  fi

  printf '%-26s %-17s %-17s %-8s %s\n' "$label" "$dom" "${ovs:--}" "${code:--}" "$verdict"
}

check "HTTP  $HOST:8118"  "http://$HOST:8118"
check "SOCKS $HOST:1080"  "socks5h://$HOST:1080"
check "HTTP  $HOST:8119"  "http://$HOST:8119"
echo
echo "合格标准：8118 和 1080 显示「国内直连」；8119 显示「全量绕出」是对的（它是刻意的对照组）。"
