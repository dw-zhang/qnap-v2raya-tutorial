# 在 QNAP NAS 上装 v2rayA：透明代理 + 自动分流 + 全屋共享

> 面向**国内网络家庭宽带 + QNAP NAS** 的完整操作手册。
> 从零开始，按第 0 步到第 11 步顺序做完即可。每一步都写清三件事：
> **敲什么命令 → 应该看到什么 → 没看到怎么办**。
>
> 不需要懂 xray 配置，不需要手写路由规则。

---

## 12 步总览

先看这张表，知道自己在哪、下一步干什么。

| 步骤 | 做什么 | 成功标志 | 必需? |
|:--:|---|---|:--:|
| **0** | 装 Container Station、开 SSH、登录验证 | `$D version` 有输出 | 必需 |
| **1** | 设置 `$D` / `$NAS_IP` 两个变量 | `echo $NAS_IP` 有值 | 必需 |
| **2** | **下载镜像**（国内最容易卡在这里） | `$D images` 看到 v2raya | 必需 |
| **3** | 创建配置目录并授权 | 目录存在、属主 1000 | 必需 |
| **4** | 上传 compose，启动 3 个容器 | 三个容器 `Up` | 必需 |
| **5** | 打开面板，创建管理员账号 | 能登录 `:2017` | 必需 |
| **6** | 导入订阅 → 更新 → 连接 | 服务器页有节点 | 必需 |
| **7** | 打开透明代理，**填 20173** | 面板显示已连接 | 必需 |
| **8** | 验证分流 | 国内/海外出口 IP 不同 | 必需 |
| **9** | 局域网设备接入 | 手机能上 Google | 推荐 |
| **10** | NAS 自带浏览器单独设代理 | Browser Station 能上外网 | 可选 |
| **11** | GitHub 加速 | `git clone` 不超时 | 可选 |

> **最小可用路径：0 → 8。** 做完这 9 步，NAS 本机所有程序就已经自动翻墙且自动分流了。
> 第 9 步是让手机、电脑也蹭上；第 10、11 步是补外围。

---

## 做之前：确认你有这四样东西

1. **一台 QNAP NAS**。Container Station 没装也没关系，第 0 步会带你装。
2. **SSH 能登录**。QTS 里打开：`控制台 → 网络和文件服务 → Telnet/SSH → 启用 SSH`。
3. **账号有 sudo 权限**。QNAP 的 `admin` 组账号一般都有；后面改 iptables 必须要。
4. **一个订阅链接**（机场或自建都行，v2ray/xray 系）。没有订阅的话这套东西没有出口节点，装了也没用。

还需要一台电脑来操作（Mac / Windows 都行），和 NAS 在同一个局域网。

**实测环境**（版本不必完全一致，大版本接近即可）：

| 项目 | 版本 |
|---|---|
| NAS | QNAP，QTS **5.2.9**，内核 `5.10.60-qnap`，x86_64 |
| Container Station | Docker **27.1.2-qnap8** / Compose **v2.29.1-qnap2** |
| v2rayA | `mzz2017/v2raya:v2.5.10`（内置 core 基于 xray-core） |
| 面板 | v2rayA 自带 Web UI，端口 `2017` |

ARM 机型（`aarch64`）也能跑，镜像支持多架构，步骤完全一样。

---

## 最终效果

```
┌──────────────┐  填 NAS_IP:8118   ┌─────────────────────────────────┐
│ 手机 / 电脑   │ ────────────────► │                                 │
└──────────────┘                   │   NAS (QNAP)                    │
                                   │                                 │
┌──────────────┐   无需任何配置     │   v2rayA ── 自动分流 ──┐        │
│ NAS 本机程序  │ ────────────────► │     │                 ├─ 国内 → 直连
└──────────────┘   (iptables 拦截)  │     └─────────────────┴─ 海外 → 节点
                                   │                                 │
                                   └─────────────────────────────────┘
```

- **NAS 本机**：所有程序零配置自动分流（下载器、Docker、Shell 都算）。
- **局域网设备**：填一个代理地址就行，端口本身已经带分流，国内站点不会绕路。
- **国内**：直连，速度和不开代理一样。
- **海外**：走订阅节点，多节点自动选最快的。

原理不展开，全放在[附录 C](#附录-c为什么必须这么配)，卡住了再看。

---

# 第 0 步：装 Container Station、开 SSH、登录验证

### 做什么

这一步装的是**唯一的图形界面软件**，后面全部在命令行和网页里操作。

### 0.1 安装 Container Station（已装可跳过）

在 QTS 桌面打开 **App Center** → 搜索 `Container Station` → 安装 → 打开。

看到 Container Station 的主界面就说明 Docker 服务已经在跑了。**不需要**在里面新建任何容器，
后面用命令行创建。

### 0.2 打开 SSH

QTS 桌面 → **控制台** → **网络和文件服务** → **Telnet/SSH** → 勾选「启用 SSH 连接」→ 应用。

端口保持默认 `22`。

### 0.3 登录并验证

在**你自己的电脑**上打开终端（Windows 用 PowerShell 或 Windows Terminal）：

```bash
ssh admin@192.168.1.10
```

> 把 `192.168.1.10` 换成你 NAS 的实际 IP，`admin` 换成你的账号。
> NAS IP 不知道的话：QTS 桌面右下角网络图标，或路由器后台的设备列表。

登录成功后，在 NAS 上执行：

```bash
uname -m
cat /etc/version
ls -l /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
sudo -v
```

### 应该看到

```
x86_64                        ← 或 aarch64（ARM 机型）
QTS 5.2.x 2024xxxx            ← QTS 5.x 都行
-rwxr-xr-x ... docker         ← 文件存在
[sudo] password for admin:    ← 输入密码后无报错
```

### 没成功怎么办

| 现象 | 原因 | 处理 |
|---|---|---|
| `Connection refused` / `timed out` | SSH 没开 | QTS：控制台 → 网络和文件服务 → 启用 SSH |
| `Permission denied` | 账号或密码错 | 换 `admin` 账号试；密码是 QTS 登录密码 |
| `ls: No such file` | Container Station 没装 / 路径不同 | 先装 Container Station；或 `find /share -name docker -path '*container-station*'` 找真实路径 |
| `sudo: command not found` | 用的不是管理员账号 | 用 `admin` 组账号登录 |

> **记住这个路径**：QNAP 的 `docker` 不在 `PATH` 里，后面统一用
> `/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker`。

---

# 第 1 步：设置两个变量

### 做什么

后面所有命令都要用到 docker 路径和 NAS IP。先存成变量，命令就能直接复制粘贴，不用每次手改。

### 命令

**在 NAS 的 SSH 窗口里**执行：

```bash
export NAS_IP=192.168.1.10
export D=/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
```

只改第一行的 IP，改成你自己 NAS 的地址。然后验证：

```bash
echo "$NAS_IP"
echo "$D"
$D version --format '{{.Server.Version}}'
```

### 应该看到

```
192.168.1.10
/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
27.1.2-qnap8
```

最后一行是 Docker 版本号，有数字就说明 Docker 正常工作。

### 注意

`export` **只对当前这个 SSH 窗口有效**。关掉窗口重连，要重新执行这两行。
嫌麻烦可以写进 `~/.profile`，但不建议——万一写错了会影响所有登录。

---

# 第 2 步：下载镜像（国内网络必看）

### 做什么

把 `v2raya` 和 `socat` 两个镜像拉到 NAS 本地。

**这一步是整篇教程最容易失败的地方**：`docker.io` 在国内基本拉不动，而
`docker compose up` 一旦拉不到镜像就会直接失败，后面全做不了。所以单独拎出来先解决。

### 2.1 先试一下直连

```bash
timeout 30 $D pull mzz2017/v2raya:v2.5.10
```

三种结果，对号入座：

| 你看到的 | 含义 | 下一步 |
|---|---|---|
| 出现 `Pulling from mzz2017/v2raya` + 进度条 | 直连可用 | 等它拉完，跳到 [2.5](#25-确认镜像到位) |
| `TLS handshake timeout` / `connection reset` / `i/o timeout` | 被墙 | 做 [2.2](#22-一键拉取推荐) |
| 30 秒后什么都没发生，命令被 `timeout` 杀掉 | 卡住 | 做 [2.2](#22-一键拉取推荐) |

> 如果提示 `timeout: command not found`，去掉 `timeout 30` 直接跑，卡住就按 `Ctrl+C`。

### 2.2 一键拉取（推荐）

脚本会按「直连 → 国内源 1 → 国内源 2 → ...」的顺序自动试，成功后把镜像重新打成标准名，
`docker-compose.yaml` 一个字都不用改。

**先把脚本弄到 NAS 上**，两种方式任选：

**方式 A：电脑上已经有这个仓库**（从 GitHub 下载的 zip 解压后）

```bash
# 在你自己的电脑上、仓库根目录执行（不是 NAS 里）
scp scripts/pull-images.sh admin@192.168.1.10:/tmp/
```

然后回 NAS 执行：

```bash
sh /tmp/pull-images.sh
```

**方式 B：NAS 能访问 GitHub**

```bash
cd /share/Container
git clone https://github.com/dw-zhang/qnap-v2raya-tutorial.git
cd qnap-v2raya-tutorial
sh scripts/pull-images.sh
```

要连 FastGithub 的镜像一起拉，加一个参数：

```bash
# 方式 A
sh /tmp/pull-images.sh --with-fastgithub

# 方式 B（在仓库目录里）
sh scripts/pull-images.sh --with-fastgithub
```

> **两种都不行**（GitHub 打不开、手边也没有仓库文件）→ 直接看
> [2.3 手动换源](#23-手动换源脚本用不了时)。那个方法只需要手敲 3 条命令，不需要任何文件。

### 2.3 手动换源（脚本用不了时）

不需要任何脚本文件，一条一条试。**哪条成功了就停**：

```bash
# v2rayA 主镜像
$D pull docker.1ms.run/mzz2017/v2raya:v2.5.10
$D pull docker.m.daocloud.io/mzz2017/v2raya:v2.5.10
$D pull docker.xuanyuan.me/mzz2017/v2raya:v2.5.10
```

拉成功后，**必须**重新打成标准名（否则 compose 找不到）：

```bash
$D tag docker.1ms.run/mzz2017/v2raya:v2.5.10 mzz2017/v2raya:v2.5.10
```

> 把 `docker.1ms.run` 换成你实际成功的那一个。

然后用同样的方式拉 socat：

```bash
$D pull docker.1ms.run/alpine/socat:latest
$D tag docker.1ms.run/alpine/socat:latest alpine/socat:latest
```

**当前可用的源**（写这份文档时实测，随时会变）：

| 镜像源 | 状态 | 备注 |
|---|---|---|
| `docker.1ms.run` | 可用 | 首选，支持大部分官方镜像 |
| `docker.m.daocloud.io` | 可用 | DaoCloud，老牌稳定 |
| `docker.xuanyuan.me` | 可用 | 备用 |
| `docker.1panel.live` | 时好时坏 | 不稳定 |
| `dockerproxy.net` | 已停 | 返回 404，别用 |

自己测哪个还活着：

```bash
for m in docker.1ms.run docker.m.daocloud.io docker.xuanyuan.me; do
    printf "%-28s " "$m"
    curl -s -m 6 -o /dev/null -w "%{http_code}\n" "https://$m/v2/"
done
```

返回 `401` 或 `200` = 活着；`000` 或超时 = 挂了。

### 2.4 全都不行时的兜底

**办法一：换网络（最快）**

手机开热点，NAS 连热点，重新跑 2.1。NAS 的 WiFi 在 QTS 里配，或者直接插网线到手机（USB 网络共享）。

**办法二：离线导入**

在**能正常上网的电脑**上（Mac 装了 Docker Desktop，或任何 Linux）：

```bash
docker pull mzz2017/v2raya:v2.5.10
docker save mzz2017/v2raya:v2.5.10 | gzip > v2raya.tgz

docker pull alpine/socat:latest
docker save alpine/socat:latest | gzip > socat.tgz
```

传到 NAS：

```bash
scp v2raya.tgz socat.tgz admin@192.168.1.10:/tmp/
```

回到 NAS 导入：

```bash
gunzip -c /tmp/v2raya.tgz | $D load
gunzip -c /tmp/socat.tgz   | $D load
```

### 2.5 确认镜像到位

```bash
$D images | grep -E "v2raya|socat"
```

应该看到两行，类似：

```
mzz2017/v2raya    v2.5.10   a1b2c3d4e5f6   580MB
alpine/socat      latest    f6e5d4c3b2a1   12MB
```

**关键**：`REPOSITORY` 必须是 `mzz2017/v2raya` 和 `alpine/socat`，**不能带 `docker.1ms.run/` 前缀**。
带前缀说明你忘了 `docker tag`，回 2.3 补上。

> 第 0～2 步做完，最难的部分已经过去了。后面都是点鼠标。

---

# 第 3 步：创建配置目录

### 做什么

给 v2rayA 建两个目录：一个存配置（账号、节点、规则），一个存日志。

**不建这个目录，容器重建后账号和节点全部清零。**

### 命令

```bash
sudo mkdir -p /share/Container/v2raya/config /share/Container/v2raya/logs
sudo chown -R 1000:1000 /share/Container/v2raya
ls -ld /share/Container/v2raya /share/Container/v2raya/config
```

### 应该看到

```
drwxr-xr-x 4 1000 1000 4096 ... /share/Container/v2raya
drwxr-xr-x 2 1000 1000 4096 ... /share/Container/v2raya/config
```

属主是 `1000 1000`（不是 `admin`）才对——容器里的 v2raya 进程用 uid 1000 跑，
不是这个属主就写不进数据库。

### 没成功怎么办

`/share/Container` 不存在（部分机型）：

```bash
ls -ld /share/Container
# 如果没有，换成实际路径：
sudo mkdir -p /share/CACHEDEV1_DATA/Container/v2raya/config /share/CACHEDEV1_DATA/Container/v2raya/logs
sudo chown -R 1000:1000 /share/CACHEDEV1_DATA/Container/v2raya
```

后面所有 `/share/Container/v2raya` 都要换成对应路径。

---

# 第 4 步：上传 compose 并启动容器

### 做什么

把编排文件放到 NAS 上，然后一次性启动 3 个容器：

- `v2raya` —— 主程序
- `v2raya-lan` —— 局域网端口转发
- `v2raya-markfix` —— QTS 的 mark 修复守护（没有它一开透明代理就全网瘫痪）

### 4.1 把文件放上去

**方式 A：scp（推荐）**

在**你自己的电脑**上执行（不是 NAS 里，注意这里没有 `$NAS_IP` 变量，要写真实 IP）：

```bash
scp docker-compose.yaml admin@192.168.1.10:/share/Container/v2raya/
```

**方式 B：Container Station 图形界面**

Container Station → 文件 → 浏览到 `/Container/v2raya` → 上传 `docker-compose.yaml`。

**方式 C：NAS 上已经有仓库**

```bash
cp /share/Container/qnap-v2raya-tutorial/docker-compose.yaml /share/Container/v2raya/
```

**方式 D：什么都没有（GitHub 打不开、也没传文件）**

在 NAS 上直接粘贴下面整段，一次性生成编排文件。功能与仓库里的完整版一致，
只是去掉了注释：

```bash
cat > /share/Container/v2raya/docker-compose.yaml <<'YAML'
services:
  v2raya:
    image: mzz2017/v2raya:v2.5.10
    container_name: v2raya
    restart: unless-stopped
    network_mode: host
    privileged: true
    command: ["--nftables-support=off", "--ipv6-support=off"]
    dns: [223.5.5.5, 119.29.29.29]
    environment:
      TZ: Asia/Shanghai
      IPTABLES_MODE: legacy
    volumes:
      - /share/Container/v2raya/config:/etc/v2raya
      - /share/Container/v2raya/logs:/var/log/v2raya
      - /lib/modules:/lib/modules:ro
      - /etc/localtime:/etc/localtime:ro

  v2raya-lan:
    image: alpine/socat:latest
    container_name: v2raya-lan
    restart: unless-stopped
    network_mode: host
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        IP=$$(/sbin/ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $$2}' | cut -d/ -f1 | head -1)
        if [ -z "$$IP" ]; then IP=0.0.0.0; fi
        socat TCP-LISTEN:1080,fork,reuseaddr,bind=$$IP TCP:127.0.0.1:20173 &
        socat TCP-LISTEN:8118,fork,reuseaddr,bind=$$IP TCP:127.0.0.1:20172 &
        socat TCP-LISTEN:8119,fork,reuseaddr,bind=$$IP TCP:127.0.0.1:20171 &
        wait

  v2raya-markfix:
    image: mzz2017/v2raya:v2.5.10
    container_name: v2raya-markfix
    restart: unless-stopped
    network_mode: host
    privileged: true
    environment:
      TZ: Asia/Shanghai
      IPTABLES_MODE: legacy
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        while true; do
          iptables -t mangle -C OUTPUT -p tcp -m mark --mark 0x80/0x80 -j RETURN 2>/dev/null || \
            iptables -t mangle -I OUTPUT 1 -p tcp -m mark --mark 0x80/0x80 -j RETURN
          sleep 30
        done
YAML
```

粘贴完不会有任何输出，用下面这条确认文件写进去了：

```bash
wc -l /share/Container/v2raya/docker-compose.yaml    # 应该是 50 行左右
```

确认文件在位：

```bash
ls -l /share/Container/v2raya/docker-compose.yaml
```

### 4.2 启动

```bash
cd /share/Container/v2raya
$D compose up -d
```

### 4.3 确认三个容器都起来了

```bash
$D ps --filter name=v2raya --format 'table {{.Names}}\t{{.Status}}'
```

应该看到：

```
NAMES             STATUS
v2raya            Up 30 seconds (healthy)
v2raya-lan        Up 30 seconds
v2raya-markfix    Up 30 seconds
```

三个都是 `Up` 就过了。`(healthy)` 可能要等 20 秒才出现，正常。

### 4.4 启动失败对照

| 报错 | 原因 | 处理 |
|---|---|---|
| `no such image: mzz2017/v2raya:v2.5.10` | 镜像没拉下来，或 tag 名不对 | 回[第 2 步](#第-2-步下载镜像国内网络必看) |
| `permission denied while trying to connect to the Docker daemon` | 没用 sudo | 命令前加 `sudo` |
| `Bind for 0.0.0.0:2017 failed: port is already allocated` | 2017 端口被占 | `netstat -tlnp \| grep 2017` 找到占用者，停掉 |
| `docker: 'compose' is not a docker command` | 老版本只有 `docker-compose` | 改用 `docker-compose up -d`（同为 container-station/bin 目录下） |
| `no configuration file provided` | 不在 compose 文件所在目录 | `cd /share/Container/v2raya` 再执行 |
| 日志里 `getaddrinfo(""): Name does not resolve` | compose 文件被改过，`$IP` 没写成 `$$IP` | 用仓库原版 compose，别手改变量 |

看日志：

```bash
$D logs --tail 30 v2raya
```

---

# 第 5 步：打开面板，创建管理员账号

### 做什么

用浏览器打开 v2rayA 的 Web 面板，建第一个账号。

### 操作

浏览器访问（**在你自己电脑上**，不是 NAS 上）：

```
http://192.168.1.10:2017
```

第一次打开会让你创建管理员账号。填用户名 + 密码，点确定。

> **这个密码只存在 NAS 本地**，忘了没法找回，只能删数据库重来。记牢，或者存密码管理器。

### 应该看到

进入主界面，左侧有「服务器」「订阅」「设置」「导入」这些菜单。

### 没成功怎么办

| 现象 | 原因 | 处理 |
|---|---|---|
| 页面打不开 / 一直转圈 | 容器没起来 | 回 4.3 看容器状态 |
| `Connection refused` | 2017 端口没监听 | `netstat -tln \| grep 2017`；没有就 `$D logs v2raya` |
| 打开是别的页面 | 2017 被别的服务占了 | 换端口：改 compose 里的 `2017`，但 v2rayA 面板端口由程序决定，需加 `--address` 参数 |

---

# 第 6 步：导入订阅 → 更新 → 连接

### 做什么

把你的机场订阅导进来，拉取节点列表，选节点连接。

### 操作顺序

**① 导入订阅**

左侧「导入」→ 选「订阅链接」→ 填两栏：

- 备注：随便写，比如 `主力机场`
- 地址：你的订阅 URL（`https://...` 开头那一长串）

点确定。

**② 更新订阅（关键，很多人漏这步）**

左侧「订阅」→ 找到刚建的那条 → 点右上角「**更新**」。

等几秒，它会去拉节点。成功后会提示拉到了多少个节点。

**③ 连接**

左侧「服务器」→ 会看到节点列表（按国家/分组排列）→ 勾选你想用的节点（或勾整组）→ 点右上角「**连接**」。

### 应该看到

- 「服务器」页节点前面出现延迟数字（比如 `45ms`）
- 顶部/状态区显示「已连接」
- `config.json` 被生成出来：

```bash
ls -l /share/Container/v2raya/config/config.json
```

### 没成功怎么办

| 现象 | 原因 | 处理 |
|---|---|---|
| 更新转圈后提示失败 | NAS 解析不了订阅域名 | compose 里已设 `dns: 223.5.5.5`，确认没删；再试 `nslookup 你的订阅域名 223.5.5.5` |
| 更新成功但节点列表是空的 | 订阅格式不支持 | v2rayA 只吃 v2ray/xray 系（vmess/vless/ss/trojan）；试用「导入 → 节点」贴单条链接验证 |
| 节点全是 `-1ms` / 超时 | 节点本身不通，或本地网络拦了 | 换节点分组；或在「服务器」页点「测速」重测 |
| 连接后立刻断开 | 节点被封 | 换节点 |

看日志：

```bash
$D logs --tail 50 v2raya
```

---

# 第 7 步：打开透明代理（最关键的一步）

### 做什么

让 NAS 本机的所有程序不用填代理就自动走分流，同时把「分流入站端口」开出来给局域网用。

### 操作

左侧「**设置**」，按下表填。不同版本措辞略有差异，认关键词：

| 设置项 | 填什么 | 为什么 |
|---|---|---|
| 透明代理 / 系统代理 | 选「**透明代理**」 | 系统代理只影响部分程序，透明代理才是全局 |
| 透明代理模式 | **白名单模式（whitelist）** | 名单内的直连，其余走代理 = 国内直连、海外翻墙 |
| 透明代理类型 | `redirect` | QNAP 上 `tproxy` 需要额外内核模块，redirect 更稳 |
| 端口：SOCKS5 | `20170` | 全量，不用管 |
| 端口：HTTP | `20171` | 全量，不用管 |
| 端口：HTTP（PAC / 分流） | `20172` | 分流端口，局域网 8118 转到这里 |
| 端口：**SOCKS5（PAC / 分流）** | `20173` | **必须手动填！默认是 0（关闭）** |
| DNS 劫持 | 关 | 家用没必要，开了多一个故障点 |
| 排除接口 | `docker*,veth*,wg*,ppp*,br-*` | 保持默认，防止容器流量成环 |

点「保存」。

> **为什么 20173 必须填**：不填的话，走 SOCKS5（1080）的设备只有全量代理、没有分流——
> 能上 Google，但国内站点也会被绕到节点上，变慢甚至打不开。HTTP（8118）不受影响，
> 因为 20172 是独立开的。原理见[附录 C.3](#c3-socks-分流端口默认是关的)。

保存后 core 会重启，**NAS 会断网 5～10 秒**，属正常。

### 应该看到

设置页顶部显示「运行中」，透明代理那一栏是开启状态。

### 确认 20173 真的生效了

```bash
sudo grep -o '"inboundTag":\[[^]]*\]' /share/Container/v2raya/config/config.json | sort -u
```

应该看到两行：

```
"inboundTag":["rule-http_ipv4","rule-socks_ipv4"]
"inboundTag":["transparent"]
```

**如果看到的是 `"rule-socks"`（没有 `_ipv4` 后缀），说明 20173 没填成功**，回上表重填、保存。

---

# 第 8 步：验证分流

### 做什么

确认「国内直连、海外走节点」真的生效了。这是整套系统唯一需要验收的地方。

### 命令（在 NAS 上执行）

```bash
echo -n "国内出口: "; curl -s -m 10 http://ip.3322.net; echo
echo -n "海外出口: "; curl -s -m 12 https://ipinfo.io/ip; echo
```

### 应该看到

```
国内出口: 163.125.144.105      ← 你家宽带 IP
海外出口: 36.231.107.250       ← 节点 IP
```

**两个 IP 不一样 = 成功。**

如果两个一样，说明没分流：
- 两个都是家宽 IP → 透明代理没生效，回第 7 步
- 两个都是节点 IP → 走了全量代理，回第 7 步检查 20173

### 再加一层验证（测局域网端口）

在**你自己的电脑**上跑（仓库目录里）：

```bash
cd qnap-v2raya-tutorial
chmod +x scripts/verify-split.sh
./scripts/verify-split.sh 192.168.1.10
```

### 应该看到

```
本机直连国内出口 IP : 203.0.113.10   (仅供参考)
全量端口(8119)国内出口: 198.51.100.20

代理                       国内出口          海外出口          google   分流判定
-------------------------- ----------------- ----------------- -------- --------
HTTP  192.168.1.10:8118    203.0.113.10      198.51.100.20     200      国内直连
SOCKS 192.168.1.10:1080    203.0.113.10      198.51.100.20     200      国内直连
HTTP  192.168.1.10:8119    198.51.100.20     198.51.100.20     200      全量绕出
```

前两行「国内直连」就对了。第三行显示「全量绕出」是对的——8119 是刻意留的对照组。

> 这套判定不依赖本机有没有挂代理：它拿全量端口（8119）的国内出口当基准，
> 谁和它一样就说明谁被绕出去了。所以在 NAS 本机跑同样准。

### 再补两条手工检查

```bash
# 1) markfix 是否在位：第一行应该是 RETURN ... mark match 0x80/0x80
sudo iptables -t mangle -L OUTPUT -n -v | head -3

# 2) 入站端口是否齐全
netstat -tln | grep -E ':(2017[0-9]|52345|1080|8118) '
```

预期能看到 `2017`、`20170`~`20173`、`52345`，以及 `1080` / `8118` / `8119`。

第一条如果第一行不是 `RETURN`，等 30 秒让 markfix 补插；还是没有就 `$D logs v2raya-markfix`。

---

# 第 9 步：让局域网设备用上

### 做什么

手机、电脑、平板填 NAS 的代理地址，就能蹭上这条路。

**只需要记两个端口**：

| 协议 | 地址 | 说明 |
|---|---|---|
| HTTP / HTTPS | `NAS_IP:8118` | 浏览器、大部分 App 用这个 |
| SOCKS5 | `NAS_IP:1080` | 支持 SOCKS5 的 App 用这个 |

两个都**自动分流**，国内站点不会绕路。不要用 `8119`（那个是全量代理，只在特殊场景用）。

### 各平台怎么填

**macOS**
`系统设置 → 网络 → 你的网络 → 详细信息 → 代理`
- 网页代理（HTTP）：`192.168.1.10` 端口 `8118`
- 安全网页代理（HTTPS）：同上
- 套接字代理（SOCKS5）：`192.168.1.10` 端口 `1080`

**Windows 10/11**
`设置 → 网络和 Internet → 代理 → 手动设置代理`
- 地址 `192.168.1.10`，端口 `8118`，打开「使用代理服务器」

**iPhone / iPad**
`设置 → 无线局域网 → 点当前 WiFi 右边的 ⓘ → 配置代理 → 手动`
- 服务器 `192.168.1.10`，端口 `8118`

**Android**
`WiFi → 长按当前网络 → 修改网络 → 高级 → 代理 → 手动`
- 主机名 `192.168.1.10`，端口 `8118`

**命令行（临时验证）**

```bash
curl -x http://192.168.1.10:8118 https://www.google.com -I
```

### 应该看到

手机浏览器能打开 `google.com`，同时打开 `taobao.com` 速度正常（不卡）。

### 注意

这三个端口**没有鉴权**，局域网里任何设备都能用。家里用没问题；
公司/宿舍环境不想开放就停掉：

```bash
$D stop v2raya-lan
```

**绝对不要**把 8118 映射到公网。要远程用就走 Tailscale / WireGuard。

---

# 第 10 步：NAS 自带浏览器（Browser Station）

### 做什么

Browser Station 里的浏览器跑在**独立的网络命名空间**里，NAS 的透明代理抓不到它。
所以要单独给它填代理。

### 操作

打开 Browser Station 里的浏览器（SeaMonkey）：

`编辑 → 首选项 → 高级 → 网络 → 连接 → 手动代理配置`

| 项 | 填 |
|---|---|
| HTTP 代理 | `192.168.1.10` 端口 `8118` |
| 也对 HTTPS 使用此代理 | **勾上** |
| SOCKS 代理 | 留空 |

保存后重开页面。

### 为什么不能填 127.0.0.1

浏览器在独立 netns 里，它的 `127.0.0.1` 是它自己，不是 NAS。必须填 NAS 的局域网 IP。

### 没成功怎么办

| 现象 | 处理 |
|---|---|
| 填了还是打不开 | 确认端口是 `8118` 不是 `20172`（跨 netns 只能用 LAN 端口） |
| 提示证书错误 | 正常，点继续；或在浏览器里导入代理的 CA |

---

# 第 11 步：GitHub 加速（可选）

三条路，按省事程度排序。第 9 步做完后，**方法一就够了**。

### 11.1 让 git 走 NAS 代理（最简单）

在**你自己的电脑**上：

```bash
git config --global http.https://github.com.proxy http://192.168.1.10:8118
git config --global https.https://github.com.proxy http://192.168.1.10:8118
```

只对 `github.com` 生效，不影响国内 Git 仓库。

验证：

```bash
git clone --depth 1 https://github.com/torvalds/linux.git /tmp/linux-test
```

能开始下载就对了，`Ctrl+C` 中断即可。

取消：

```bash
git config --global --unset http.https://github.com.proxy
git config --global --unset https.https://github.com.proxy
```

### 11.2 FastGithub（针对 GitHub 做优选 IP）

适合「代理不稳定，但想要 GitHub 单独加速」的情况。配置文件在
[`fastgithub/docker-compose.yaml`](fastgithub/docker-compose.yaml)。

**① 建目录**（NAS 上）

```bash
sudo mkdir -p /share/Container/fastgithub/cacert /share/Container/fastgithub/logs
sudo chown -R 1000:1000 /share/Container/fastgithub
```

> `cacert` **必须是空目录**。镜像里预置了一对 2021 年的公开 CA 私钥（等于已泄露），
> 挂个空目录遮住它，首次启动才会现场生成只有你这台机器有的新证书。

**② 启动**

```bash
mkdir -p /share/Container/fastgithub
cd /share/Container/fastgithub
# 把仓库里的 fastgithub/docker-compose.yaml 放到这个目录
$D compose up -d
```

**③ 确认监听**

```bash
netstat -tln | grep 38457
```

必须有 `127.0.0.1:38457`。没有就 `$D logs fastgithub` 看日志。

**④ 让 git 信任它的 CA**

```bash
sudo bash scripts/fastgithub-refresh-ca.sh
git config --global http.https://github.com.proxy http://127.0.0.1:38457
git config --global http.sslCAInfo /share/Container/fastgithub/cacert/combined-ca.pem
```

**⑤ 验证**

```bash
curl -x http://127.0.0.1:38457 -I https://github.com
git clone --depth 1 https://github.com/torvalds/linux.git /tmp/linux-test
```

> FastGithub 只监听回环，**局域网设备用不了**。要共享得放开 compose 末尾的
> `fastgithub-lan`，但那等于在局域网开了个通用 HTTP 代理，自己权衡。

### 11.3 拉 GitHub Release 慢

用 NAS 的代理下载：

```bash
curl -L -x http://127.0.0.1:8118 -O https://github.com/xxx/yyy/releases/download/v1.0/file.tar.gz
```

或者直接在能翻墙的电脑上下好，`scp` 传过去。

---

# 出问题了：按现象查

| 现象 | 最可能的原因 | 怎么修 |
|---|---|---|
| **镜像拉不下来**，一直 timeout | docker.io 被墙 | 回[第 2 步](#第-2-步下载镜像国内网络必看)，用镜像源或离线导入 |
| 能上 Google，但**国内网站很慢/打不开** | 用了全量端口，或 20173 没填 | 确认客户端填 8118/1080；确认设置里 SOCKS5（PAC）端口 = 20173 |
| **一开透明代理整机断网**，日志疯狂自连 | QTS 抹掉了 `SO_MARK` | 确认 `v2raya-markfix` 在跑；手工补规则见[附录 C.1](#c1-为什么需要-markfix) |
| 透明代理开了但**出口还是家宽 IP** | `IPTABLES_MODE` 不是 legacy | 确认 compose 里 `IPTABLES_MODE: legacy` 和 `--nftables-support=off` |
| 面板打不开 | 容器没起 / 端口被占 | `$D ps`；`$D logs v2raya`；`netstat -tln \| grep 2017` |
| 订阅更新失败 | DNS 解析不了 | 确认 compose 里 `dns: 223.5.5.5`；`nslookup 订阅域名 223.5.5.5` |
| 节点全部超时 | 节点被封 / 本地拦 | 换节点；换订阅；在别的设备上试同一订阅 |
| 端口起不来，日志 `getaddrinfo("")` | compose 里 `$IP` 被插值成空 | 用仓库原版 compose（变量要写 `$$IP`） |
| 自定义分流规则不生效 | v2rayA 2.5.10 忽略 `routingA` | 放弃这条路，见[附录 C.4](#c4-为什么不要用自定义分流规则) |
| 容器重建后账号节点全丢 | config 没挂载 | 检查 compose 的 `volumes` |
| NAS 浏览器不生效 | 独立 netns | 回[第 10 步](#第-10-步nas-自带浏览器browser-station)手动填代理 |
| 日志 `whitelist matching remains linear` | QNAP 没 ipset | 纯性能提示，条目少时无感，忽略 |

**万能三连**（先跑这三个再问人）：

```bash
$D ps --filter name=v2raya
$D logs --tail 50 v2raya
sudo iptables -t mangle -L OUTPUT -n -v | head -5
```

---

# 日常运维

### QTS 重启后自检

```bash
$D ps --filter name=v2raya --format 'table {{.Names}}\t{{.Status}}'
sudo iptables -t mangle -L OUTPUT -n | head -3
./scripts/verify-split.sh 192.168.1.10
```

三个容器都在 + 第一行是 `RETURN ... mark match 0x80/0x80` + 分流正常 = 没问题。
`v2raya-markfix` 每 30 秒自检一次，一般不用管。

### 备份（改任何东西之前）

```bash
BK=/share/Container/v2raya/config-backup-$(date +%Y%m%d-%H%M%S)
sudo mkdir -p "$BK"
sudo cp -a /share/Container/v2raya/config/* "$BK"/
sudo cp -a /share/Container/v2raya/docker-compose.yaml "$BK"/
echo "备份到 $BK"
```

### 升级

```bash
cd /share/Container/v2raya
$D compose pull
$D compose up -d
```

升级后**必须重跑第 8 步**验证分流（大版本可能改端口语义）。

### 回滚

```bash
cd /share/Container/v2raya
$D compose down
sudo cp -a config-backup-20261017-190951/v2raya.db config/
$D compose up -d
```

### 高级：没有 sqlite3 怎么直接改配置库

QNAP 默认没有 `sqlite3` 命令（`command -v sqlite3` 为空）。**能面板改的就从面板改**，
只有批量改端口、救砖这类场景才动库：

```bash
# 1) 停容器：SQLite 会自动 checkpoint，并清掉 -wal/-shm
$D stop v2raya

# 2) 把库拉到本地（在你自己的电脑上执行）
scp admin@192.168.1.10:/share/Container/v2raya/config/v2raya.db ./

# 3) 本地用 Python 的 sqlite3 改（Python 3 自带，不用装）
python3 - <<'PY'
import sqlite3
con = sqlite3.connect("v2raya.db")
row = con.execute("SELECT value FROM system_config WHERE key='system:ports'").fetchone()
print("当前 system:ports =", row[0] if row else "MISSING")
# 要改就改，改完 commit；不改也可以只用来查看
con.execute("PRAGMA journal_mode=DELETE")
con.commit(); con.close()
PY

# 4) 传回去，属主改回 1000（否则容器写不进去）
scp ./v2raya.db admin@192.168.1.10:/tmp/v2raya.db
ssh admin@192.168.1.10 'sudo cp /tmp/v2raya.db /share/Container/v2raya/config/v2raya.db \
  && sudo chown 1000:1000 /share/Container/v2raya/config/v2raya.db \
  && sudo rm -f /share/Container/v2raya/config/v2raya.db-wal /share/Container/v2raya/config/v2raya.db-shm'

# 5) 起容器
$D start v2raya
```

> 库里字符串值是 **JSON 编码**的（带引号），比如 `"20173"` 而不是 `20173`。改的时候别把引号弄丢。

---

# 安全须知

公开这份教程 / 发布仓库时，这几点必须注意：

1. **绝对不要提交**：订阅链接、节点 UUID、节点域名、面板密码、SSH 密码、`v2raya.db`。
   `v2raya.db` 里有 JWT 密钥和账号 hash，`config.json` 里有节点凭据。
2. `.gitignore` 已经排除了这些，**不要**用 `git add -f` 强行加进来。
3. 局域网代理端口（`1080` / `8118` / `8119`）**没有鉴权**，任何能连到 NAS 的设备都能借此出墙。
   不想开放就 `$D stop v2raya-lan`。
4. **不要把 8118 映射到公网**。要远程用就走 Tailscale / WireGuard / 第 11 步之外的方案。
5. FastGithub 的 `cacert` 里那对私钥**只属于你这台机器**，别外传。

发布前自检一遍：

```bash
git status --short          # 有没有意外加进来的 db / 证书 / 配置
git ls-files | grep -Ei 'v2raya\.db|config\.json|cacert|\.pem|\.key'
```

第二条**应该没有任何输出**。有输出就 `git rm --cached <文件>` 并补进 `.gitignore`。

---

# 附录 A：端口总表

| 端口 | 监听地址 | 归属 | 用途 |
|---|---|---|---|
| `2017` | `0.0.0.0` | v2rayA | Web 面板 |
| `20170` | `127.0.0.1` | v2rayA | SOCKS5 全量（不分流） |
| `20171` | `127.0.0.1` | v2rayA | HTTP 全量（不分流） |
| `20172` | `127.0.0.1` | v2rayA | HTTP **分流** |
| `20173` | `127.0.0.1` | v2rayA | SOCKS5 **分流**（需手动开启） |
| `52345` | `127.0.0.1` | v2rayA | 透明代理入站（redirect） |
| `52353` | — | v2rayA | 内置 DNS，DNS 模块关闭时不监听 |
| `1080` | `NAS_IP` | socat | SOCKS5 分流，给局域网 |
| `8118` | `NAS_IP` | socat | HTTP 分流，给局域网 |
| `8119` | `NAS_IP` | socat | HTTP 全量，备用 |
| `38457` | `127.0.0.1` | FastGithub | GitHub 加速代理 |

---

# 附录 B：仓库文件清单

```
.
├── README.md                        # 本文
├── docker-compose.yaml              # v2rayA + socat 网桥 + markfix
├── fastgithub/
│   └── docker-compose.yaml          # GitHub 加速（可选）
├── scripts/
│   ├── pull-images.sh               # 国内拉镜像（自动换源）
│   ├── verify-split.sh              # 一键验证分流
│   └── fastgithub-refresh-ca.sh     # 重建 git 用的合并 CA
├── .gitignore
└── LICENSE
```

---

# 附录 C：为什么必须这么配

配完了能跑，这一节解释「为什么」，出问题时知道该看哪。

## C.1 为什么需要 markfix

QTS 固件在 `mangle OUTPUT` 里有一条无条件规则：

```
-j CONNMARK --restore-mark --nfmask 0xffffffff --ctmask 0xffffffff
```

它用 conntrack mark（=0）全掩码覆盖每个本地出站包的 packet mark。
而 xray 出站靠 `SO_MARK 0x80` 做「别再拦我」的标记——被抹掉之后，
`--mark 0x80 RETURN` 的旁路永远匹配不上，xray 自己的出站连接被透明代理再抓一次，
形成**无限自连**（一次请求能打出 80 多个自连），整机网络瘫痪。

修复是在 `mangle OUTPUT` 最前面插一条：

```bash
sudo iptables -t mangle -I OUTPUT 1 -p tcp -m mark --mark 0x80/0x80 -j RETURN
```

已带 `0x80` 的包直接跳过本链（也就跳过了 restore），mark 才能活下来。
`v2raya-markfix` 容器每 30 秒 `-C` 判重后补插，因为 QTS 升级/重启/防火墙重载都会清掉它。

## C.2 为什么 20171 是全量、20172 才分流

v2rayA 生成的路由规则**写死了 `inboundTag`**：

```json
{"inboundTag": ["rule-http_ipv4", "rule-socks_ipv4"], "domain": ["geosite:cn"], "outboundTag": "direct"}
{"inboundTag": ["transparent"], "domain": ["geosite:cn"], "outboundTag": "direct"}
{"balancerTag": "proxy", "port": "0-65535"}
```

`socks_ipv4` / `http_ipv4`（也就是 20170/20171）不在任何一条规则里，
流量直接命中最后那条兜底 → **全量出境**。这就是「明明有分流规则，国内网站却慢成狗」的根因。

## C.3 SOCKS 分流端口默认是关的

模板里的 `rule-socks` 是**占位符**。只有对应的 PAC 入站存在时，才会替换成真实 tag
`rule-socks_ipv4`；当 `socks5WithPac = 0` 时占位符原样保留，这条规则永远匹配不到入站。

所以设置里必须把「SOCKS5（PAC/分流）端口」填成非 0（本文用 20173）。

## C.4 为什么不要用自定义分流规则

v2rayA 面板里有「分流规则」编辑框（`system:routingA`）。**实测 v2.5.10 会忽略它**：
写入合法规则、重启后 `config.json` 依旧是内置模板，规则依旧带 `inboundTag` 限定。

不要试图用自定义 routingA 实现「所有入站统一分流」——达不到目的。
想要全局分流只有两条路：走**分流入站**（20172/20173），或走**透明代理**。

## C.5 关于 PAC（实测：没有这个东西）

`20172` 在面板里叫「HTTP（PAC）」，但它本质就是一个套用分流规则的 HTTP 代理端口，
**不是 PAC 文件服务器**：

```bash
curl -I http://127.0.0.1:20172/proxy.pac          # 400 Bad Request
curl -o /dev/null -w '%{http_code}' http://<NAS_IP>:2017/proxy.pac   # 404
```

所以不要把浏览器的「自动代理配置 URL」指向 NAS——没有这个文件。

## C.6 DNS 会不会被污染

| 问题 | 结论 |
|---|---|
| 宿主机 DNS 走哪 | QTS 自带 dnsmasq（`127.0.1.1`） |
| 会不会被污染 | 实测 `google.com` 解析到真实 IP，没有污染 |
| 走 HTTP 代理时谁解析域名 | xray 侧解析（浏览器发 `CONNECT host:443`），本机 DNS 不参与 |
| 要不要开 DNS 劫持 | 家用不必，开了多一个单点 |

## C.7 为什么 compose 里要写 `$$IP`

`docker compose` 会把 `$变量` 当自己的变量插值。`command:` 里的 shell 变量必须写
`$$IP`（转义成 `$IP`），awk 的 `$2` 要写 `$$2`。否则 `bind=` 会变成空字符串，
三个端口全部起不来，报错还很不直观：`getaddrinfo(""): Name does not resolve`。

## C.8 compose 里每一项为什么这么写

| 配置 | 作用 / 为什么必须这么写 |
|---|---|
| `network_mode: host` | 透明代理要直接改主机网络栈；容器 netns 里的 iptables 对宿主机无效 |
| `privileged: true` | 写 iptables、读 `/dev/net/tun` 需要特权 |
| `--nftables-support=off` | QNAP 内核**没有 `nf_tables` 子系统**，走 nft 路径必失败 |
| `IPTABLES_MODE: legacy` | 镜像里的 `iptables` 是包装脚本，默认走 `xtables-nft-multi`，QNAP 上只有 legacy 能用 |
| `dns: 223.5.5.5, 119.29.29.29` | 宿主机装了 Tailscale 时 `/etc/resolv.conf` 会指向 MagicDNS `100.100.100.100`，解析订阅/节点域名经常超时 |
| `volumes: config:/etc/v2raya` | 账号、节点、规则全在这里，不挂载容器一重建就清零 |
| `volumes: /lib/modules:ro` | 透明代理需要读内核模块信息 |
| `healthcheck` | 面板起没起来，`$D ps` 能直接看到 `(healthy)` |
| `v2raya-lan`（socat） | v2rayA 生成的入站全部只绑 `127.0.0.1`，局域网连不上，必须转发 |
| `v2raya-markfix` | 见 [C.1](#c1-为什么需要-markfix) |

## C.9 内置分流规则到底长什么样

v2rayA 生成的默认规则，**按顺序匹配、命中即停**：

| 顺序 | 匹配 | 去向 |
|:--:|---|---|
| 1 | 节点自己的域名（`txt00x.xxx:443`） | 直连（否则会自己代理自己） |
| 2 | `push.apple.com` 等苹果推送 | 直连 |
| 3 | `geolocation-!cn`（海外域名库） | 代理 |
| 4 | `geosite:google` | 代理 |
| 5 | `geosite:cn`（国内域名库） | 直连 |
| 6 | `geoip:hk` / `geoip:mo` | 代理 |
| 7 | `geoip:private` / `geoip:cn` / 内网段 | 直连 |
| 8 | 兜底 | 代理 |

这就是「国内走白名单直连、海外走规则代理」的实现。规则不需要你手写，
但要知道第 1 条的存在——改节点配置时如果域名写错，会掉进第 1 条导致全网直连。

---

# 附录 D：常用命令速查

```bash
# 变量（每次新开 SSH 都要设）
export D=/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
export NAS_IP=192.168.1.10

# 容器
$D ps --filter name=v2raya
$D logs --tail 50 v2raya
$D restart v2raya
$D compose up -d
$D compose down

# 验证
curl -s http://ip.3322.net; echo                    # 国内出口（应为家宽）
curl -s https://ipinfo.io/ip; echo                  # 海外出口（应为节点）
sudo iptables -t mangle -L OUTPUT -n -v | head -5   # markfix 是否在位
netstat -tln | grep -E ':(2017[0-9]|52345|1080|8118) '

# 端口连通性
curl -x http://$NAS_IP:8118 -I https://www.google.com
curl -x socks5h://$NAS_IP:1080 -I https://www.google.com
```

---

# 参考

- v2rayA：<https://github.com/v2rayA/v2rayA>
- xray-core 路由文档：<https://xtls.github.io/config/routing.html>
- geosite / geoip 数据：<https://github.com/v2fly/domain-list-community>
- FastGithub：<https://github.com/creazyboyone/FastGithub>

---

*基于 QNAP QTS 5.2.9 + Container Station（Docker 27.1.2-qnap8）实测写成，配置在生产环境跑通。*
