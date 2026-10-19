#!/bin/sh
# ==============================================================================
#  pull-images.sh —— 国内网络下拉取本教程需要的 Docker 镜像
#
#  为什么需要这个脚本：
#    docker.io 在国内经常拉不动（timeout / connection reset）。国内镜像站又
#    随时会关停，所以这里按顺序试多个源，哪个通用哪个，成功后把镜像重新
#    tag 成标准名字，docker-compose.yaml 一个字都不用改。
#
#  用法：
#    sh scripts/pull-images.sh                    # 只拉 v2rayA 三件套要用的
#    sh scripts/pull-images.sh --with-fastgithub  # 顺带拉 FastGithub
#
#  可选环境变量：
#    D=/path/to/docker     手动指定 docker 可执行文件
#    V2RAYA_TAG=v2.5.10    指定 v2rayA 版本
#
#  退出码：0 = 全部就绪；1 = 有镜像没拉下来
# ==============================================================================
set -u

V2RAYA_TAG="${V2RAYA_TAG:-v2.5.10}"

# ---- 找 docker ---------------------------------------------------------------
D="${D:-}"
if [ -z "$D" ]; then
    if [ -x /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker ]; then
        D=/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
    elif [ -x /usr/local/bin/docker ]; then
        D=/usr/local/bin/docker
    elif command -v docker >/dev/null 2>&1; then
        D=docker
    else
        echo "[FAIL] 找不到 docker 命令"
        echo "       QNAP 上它不在 PATH 里，通常是这个位置："
        echo "       /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker"
        echo "       手动指定：D=/你的/路径/docker sh $0"
        exit 1
    fi
fi
echo "[info] docker : $D"

if [ "$D" != "docker" ] && [ ! -x "$D" ]; then
    echo "[FAIL] $D 不存在或不可执行"
    echo "       先确认 Container Station 已安装并启动；或手动指定："
    echo "       D=/你的/路径/docker sh $0"
    exit 1
fi

if ! "$D" version >/dev/null 2>&1; then
    echo "[FAIL] docker 不可用（Container Station 没启动，或当前用户无权限）"
    exit 1
fi

# ---- 镜像清单 ----------------------------------------------------------------
IMAGES="mzz2017/v2raya:${V2RAYA_TAG} alpine/socat:latest"
if [ "${1:-}" = "--with-fastgithub" ]; then
    IMAGES="$IMAGES slcnx/fastgithub:latest"
fi

# ---- 镜像源（按顺序试；失效就去掉，换成当时能用的） --------------------------
MIRRORS="docker.1ms.run docker.m.daocloud.io docker.xuanyuan.me docker.1panel.live"

HAS_TIMEOUT=0
command -v timeout >/dev/null 2>&1 && HAS_TIMEOUT=1

pull_with_timeout() {
    if [ "$HAS_TIMEOUT" = "1" ]; then
        timeout 240 "$D" pull "$1" >/dev/null 2>&1
    else
        "$D" pull "$1" >/dev/null 2>&1
    fi
}

FAILED=""

pull_one() {
    img="$1"

    if "$D" image inspect "$img" >/dev/null 2>&1; then
        echo "[SKIP] $img  (本地已有)"
        return 0
    fi

    # 1) 先试直连。能通就不用镜像站，少一层依赖。
    echo "[try ] $img  直连 docker.io ..."
    if pull_with_timeout "$img"; then
        echo "[ OK ] $img"
        return 0
    fi

    # 2) 依次试国内源
    for m in $MIRRORS; do
        echo "[try ] $img  经 $m ... (最多等 240s)"
        if pull_with_timeout "$m/$img"; then
            # 重新打成标准名，compose 不用改
            if "$D" tag "$m/$img" "$img" 2>/dev/null; then
                "$D" rmi "$m/$img" >/dev/null 2>&1
                echo "[ OK ] $img  (来源 $m)"
                return 0
            fi
        fi
    done

    echo "[FAIL] $img  所有源都失败"
    FAILED="$FAILED\n  - $img"
    return 1
}

echo ""
for img in $IMAGES; do
    pull_one "$img"
    echo ""
done

# ---- 结果 --------------------------------------------------------------------
echo "=============================================================="
if [ -n "$FAILED" ]; then
    echo "以下镜像没拉下来："
    printf "%b\n" "$FAILED"
    echo ""
    echo "兜底办法（任选其一）："
    echo "  1) 换网络：手机开热点给 NAS，或先让 NAS 走已有代理"
    echo "  2) 离线导入：在能上网的电脑上"
    echo "       docker pull mzz2017/v2raya:${V2RAYA_TAG}"
    echo "       docker save mzz2017/v2raya:${V2RAYA_TAG} | gzip > v2raya.tgz"
    echo "       scp v2raya.tgz admin@<NAS_IP>:/tmp/"
    echo "     再在 NAS 上"
    echo "       gunzip -c /tmp/v2raya.tgz | $D load"
    echo "  3) 手动换源：把上面 MIRRORS 里失效的域名换成你能用的"
    exit 1
fi

echo "全部就绪。确认一下："
"$D" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'v2raya|socat|fastgithub' | sed 's/^/  /'
exit 0
