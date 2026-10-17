#!/bin/bash
# ==============================================================================
#  fastgithub-refresh-ca.sh —— 重建 git 用的合并 CA 信任链
#
#  FastGithub 是本地 HTTPS 中间人代理，它用自己的 CA 现签证书。
#  git 默认只信任系统 CA bundle，所以要把它生成的 CA 拼进一个合并文件，
#  再用 GIT_SSL_CAINFO 指向这个文件。
#
#  什么时候要跑：
#    - 首次启动 FastGithub 之后
#    - 删过 cacert/ 目录、或换了证书之后
#    - 镜像升级后
#
#  用法：sudo bash /share/Container/fastgithub/refresh-ca.sh
# ==============================================================================

FG=${FG_DIR:-/share/Container/fastgithub}
CA="$FG/cacert"
SYS=${SYS_CA:-/etc/ssl/certs/ca-certificates.crt}

[ -f "$CA/fastgithub.cer" ] || { echo "❌ 找不到 $CA/fastgithub.cer（容器还没生成证书？）"; exit 1; }
[ -f "$SYS" ] || { echo "❌ 找不到系统 CA bundle $SYS"; exit 1; }

cat "$SYS" > "$CA/combined-ca.pem"

# cer 可能是 PEM 也可能是 DER，两种都处理
if head -c 32 "$CA/fastgithub.cer" | grep -q 'BEGIN'; then
  cat "$CA/fastgithub.cer" >> "$CA/combined-ca.pem"
else
  openssl x509 -in "$CA/fastgithub.cer" -inform DER -outform PEM >> "$CA/combined-ca.pem"
fi

echo "✅ 已重建 $CA/combined-ca.pem"
echo "   证书总数: $(grep -c 'BEGIN CERTIFICATE' "$CA/combined-ca.pem")"
echo "   FastGithub CA: $(openssl x509 -in "$CA/fastgithub.cer" -noout -subject 2>/dev/null)"
echo "   指纹: $(openssl x509 -in "$CA/fastgithub.cer" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
echo
echo "接下来在 git 里用它："
echo "  git config --global http.https://github.com.proxy http://127.0.0.1:38457"
echo "  git config --global http.sslCAInfo $CA/combined-ca.pem"
