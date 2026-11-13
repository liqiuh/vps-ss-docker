# VPS Shadowsocks Docker 一键脚本

这是上一套 `Cloudflare Pages -> VPS Nginx -> Shadowsocks + v2ray-plugin` 部署的 Docker 化版本。
新脚本保留相同的 WebSocket 思路，但 Cloudflare 端改用 Worker API 自动部署，更适合新 VPS 一键安装。

支持两种模式：

- `cloudflare`：客户端连接 Cloudflare Worker，Worker 转发到 VPS 的 Docker Nginx 源站。
- `direct`：不使用 Cloudflare，客户端直接连接 VPS 的 Shadowsocks TCP/UDP 端口。

脚本支持 Ubuntu/Debian，要求使用 `root` 运行。首次运行会自动安装 Docker Engine、Compose、`jq`、
`openssl` 和二维码工具。

## 给别人或 AI 的入口

对外分享这个稳定仓库地址即可：

```text
https://github.com/liqiuh/vps-ss-docker
```

不要把 `/tree/main` 或 `raw/main/vps-ss.sh` 当成固定发布地址直接执行；`main` 会持续更新。部署时应下载
GitHub `Latest Release` 中的 `vps-ss.sh` 和 `SHA256SUMS`，校验成功后再运行。可以把
[AI_DEPLOY.md](AI_DEPLOY.md) 连同仓库地址交给 AI，其中包含需要先向用户确认的模式、端口和防火墙检查项。

## 最简单的使用方法

```bash
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/vps-ss.sh
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/SHA256SUMS
grep ' vps-ss.sh$' SHA256SUMS | sha256sum -c -
chmod +x vps-ss.sh
sudo ./vps-ss.sh
```

然后按数字菜单选择：

```text
1) 安装/切换 Cloudflare 模式
2) 安装/切换无 Cloudflare 直连模式
```

菜单会询问 VPS 对外端口，并隐藏输入 Shadowsocks 密码。端口直接回车使用默认值；密码直接回车会在
首次安装时自动生成 48 位随机十六进制密码，重新安装时则保留现有密码。

脚本默认拉取公开镜像 `ghcr.io/liqiuh/vps-ss-docker:1.2.1`，新 VPS 无需在本地编译。Docker Hub
镜像是维护者的私人备份，不作为匿名回退源。需要使用其他已登录的私有仓库时，可通过 `SS_IMAGE` 或
`FALLBACK_SS_IMAGE` 显式指定。

如果使用 Cloudflare，推荐先用 Codex Skill `$cloudflare-vps-prep` 在浏览器中生成固定格式的
`cloudflare-vps-prep.json`，然后上传到 VPS：

```bash
scp cloudflare-vps-prep.json root@VPS_IP:/root/cloudflare-vps-prep.json
```

脚本会自动发现该文件。登录 VPS 后只需运行 `./vps-ss.sh` 并选择 `1`，不再手工填写 Account ID、
workers.dev 子域名或 API Token。

安装后会创建全局管理命令：

```bash
vps-ss
```

也可以直接执行：

```bash
sudo ./vps-ss.sh install cloudflare
sudo ./vps-ss.sh install direct
```

## 推荐：Cloudflare 准备材料文件

固定 JSON 格式如下：

```json
{
  "schema": "vps-ss-cloudflare-prep/v1",
  "cloudflare": {
    "account_id": "0123456789abcdef0123456789abcdef",
    "workers_subdomain": "my-workers-name",
    "api_token": "REDACTED"
  },
  "metadata": {
    "created_at": "2026-11-13T00:00:00Z",
    "created_by": "cloudflare-vps-prep"
  }
}
```

安装包内同时提供 `cloudflare-vps-prep.example.json` 作为结构参考。不要直接上传示例文件；推荐让
`$cloudflare-vps-prep` Skill 生成包含真实账户信息且权限为 `0600` 的文件。

自动检测位置按顺序为：

```text
脚本目录/cloudflare-vps-prep.json
/root/cloudflare-vps-prep.json
```

也可以显式指定：

```bash
sudo ./vps-ss.sh install cloudflare /安全路径/cloudflare-vps-prep.json
```

或：

```bash
CF_PREP_FILE=/安全路径/cloudflare-vps-prep.json sudo -E ./vps-ss.sh install cloudflare
```

脚本会严格校验 JSON，并把材料文件权限调整为 `0600`。API Token 只从该文件读取，不会复制到
`/opt/vps-ss/.env`。材料文件仍包含有效 Token，请只保存在 root 可读目录中；全部 VPS 安装完成后，
可以在 Cloudflare 后台撤销 Token。以后重新部署 Worker 时需要重新提供有效 Token。

## 手工模式需要提前准备

### 1. Cloudflare 账户

只需要普通 Cloudflare 免费账户。不要求购买域名，默认使用：

```text
Worker:  <脚本名>.<你的子域名>.workers.dev
源站:    <VPS-IP>.sslip.io:8080
```

如果你以后要使用自己的域名，可以在 Cloudflare 给 Worker 绑定 Custom Domain，再执行：

```bash
vps-ss set-host ss.example.com
```

### 2. Account ID

在 Cloudflare 控制台右侧或账户概览中找到 32 位 `Account ID`。它不是密码，可以保存在 VPS 配置中。

### 3. API Token

在 Cloudflare 控制台创建自定义 API Token：

```text
推荐模板: Edit Cloudflare Workers
账户权限: Workers Scripts -> Write（旧界面可能显示 Edit）
资源: 只选择你要使用的那个 Cloudflare Account
```

不要使用 Global API Key，不要提供 Cloudflare 登录密码。脚本只在部署 Worker 时读取 Token，不会把 Token
写入 `/opt/vps-ss/.env`。

交互安装时直接粘贴 Token，输入过程不会显示。也可以预先把 Token 放入仅 root 可读的文件：

```bash
install -m 600 /dev/null /root/cf-token
nano /root/cf-token
CF_API_TOKEN_FILE=/root/cf-token sudo -E ./vps-ss.sh install cloudflare
```

安装完成后可以删除 `/root/cf-token`；以后重新部署 Worker 时需要再次提供 Token。

### 4. workers.dev 子域名

Cloudflare Workers 首次使用需要一个账户级 `workers.dev` 子域名，例如：

```text
my-account.workers.dev
```

脚本会先自动查询。账户尚未设置时，脚本会询问你希望使用的名称，并尝试通过 API 创建。
也可以提前在 Cloudflare 的 `Workers & Pages` 页面启用。

## 防火墙和云安全组

本机防火墙和 VPS 服务商的云安全组是两层独立规则，两边都必须允许。安装脚本只会自动修改已经启用的
UFW 或 firewalld；自定义 nftables/iptables 规则以及云厂商安全组需要自行处理。

| 用途 | Cloudflare 模式 | 无 Cloudflare 直连模式 |
| --- | --- | --- |
| SSH 管理 | TCP `22` 或当前自定义 SSH 端口 | TCP `22` 或当前自定义 SSH 端口 |
| 服务入站 | TCP `8080`，或自定义 `ORIGIN_PORT` | TCP + UDP `8388`，或自定义 `DIRECT_PORT` |
| VPS 的 TCP `443` | 不需要，TLS 在 Worker 终止 | 不需要，除非另有网站服务 |
| VPS 的 UDP `8080` | 不需要 | 不适用 |

不要在确认新规则生效前删除当前 SSH 放行规则，否则可能失去远程连接。Cloudflare 模式不需要对公网开放
容器内部的 `8388`；直连模式也不需要开放 `8080`。如果 VPS 限制出站流量，还需要允许 DNS，以及出站
TCP `80/443`，供系统软件源、Docker Registry 和 Cloudflare API 使用。

### 5. Cloudflare 源站端口

Cloudflare 模式默认源站端口为 TCP `8080`。脚本会处理已经启用的 UFW/firewalld，但云厂商控制台的
安全组仍需要你确认：

```text
允许入站 TCP 8080
```

源站即使被扫描到也要求随机路径和 Worker 注入的随机 `X-Origin-Token`，普通请求只返回 `404`。

如果 VPS 的 `8080` 已被占用，可以指定其他端口：

```bash
ORIGIN_PORT=8880 sudo -E ./vps-ss.sh install cloudflare
```

如果不用自动生成的 `sslip.io` 源站域名，可以准备一个指向 VPS 的 DNS-only 域名：

```bash
ORIGIN_HOST=origin.example.com sudo -E ./vps-ss.sh install cloudflare
```

该源站记录必须是 DNS only，不要开橙云；对外的客户端域名才使用 Worker/Cloudflare。

## 无 Cloudflare 模式

直连模式不需要任何 Cloudflare 资料，默认开放 Shadowsocks TCP/UDP `8388`：

```bash
sudo ./vps-ss.sh install direct
```

使用其他端口：

```bash
DIRECT_PORT=24443 sudo -E ./vps-ss.sh install direct
```

同时在 VPS 服务商的安全组放行相同的 TCP 和 UDP 端口。

## 自定义端口和密码

直接运行 `sudo ./vps-ss.sh` 时，菜单会交互询问端口和密码，这是推荐方式。自动化部署也可以使用环境变量：

```bash
# 直连模式
DIRECT_PORT=24443 SS_PASSWORD='custom-pass_123!' \
  sudo -E ./vps-ss.sh install direct

# Cloudflare 模式；这是 Worker 回源到 VPS 的 TCP 端口，客户端仍连接 Worker 的 443
ORIGIN_PORT=8880 SS_PASSWORD='custom-pass_123!' \
  sudo -E ./vps-ss.sh install cloudflare /root/cloudflare-vps-prep.json
```

端口允许 `1-65535`。密码允许 `8-128` 位，只能使用字母、数字和
`. _ ~ ! @ % + = , : / -`。为避免密码出现在 shell 历史中，人工部署优先使用菜单的隐藏输入；不指定密码时
脚本会自动生成强随机密码。

## 日常管理

```bash
vps-ss start
vps-ss stop
vps-ss restart
vps-ss status
vps-ss info
vps-ss info --show-secret
vps-ss link
vps-ss clash
vps-ss logs 100
vps-ss follow
vps-ss doctor
vps-ss cf-deploy
```

配置和密钥保存在：

```text
/opt/vps-ss/.env
/opt/vps-ss/config.json
```

这两个文件只允许 root 或容器内指定用户读取。`vps-ss info` 默认隐藏密码；只有 `link`、`clash` 或
`info --show-secret` 会显示完整凭据。

## 使用你自己的 Docker 仓库

镜像基于：

- `ghcr.io/shadowsocks/ssserver-rust:v1.25.0`
- `v2ray-plugin v1.5.0`
- Alpine `nginx`（Cloudflare 源站代理，与 Shadowsocks 共用同一发布镜像）
- 支持 `linux/amd64` 和 `linux/arm64`

构建并推送多架构镜像：

```bash
docker login
docker buildx create --use --name vps-ss-builder 2>/dev/null || docker buildx use vps-ss-builder
docker buildx build \
  --pull \
  --platform linux/amd64,linux/arm64 \
  --build-arg IMAGE_VERSION=1.2.1 \
  -t docker.io/你的账号/vps-ss:1.2.1 \
  -t docker.io/你的账号/vps-ss:latest \
  --provenance=true \
  --sbom=true \
  --push .
```

新 VPS 直接拉取你的镜像，不再现场构建：

```bash
SS_IMAGE=docker.io/你的账号/vps-ss:1.2.1 \
BUILD_LOCAL=0 \
sudo -E ./vps-ss.sh install cloudflare
```

或：

```bash
SS_IMAGE=docker.io/你的账号/vps-ss:1.2.1 \
BUILD_LOCAL=0 \
sudo -E ./vps-ss.sh install direct
```

## 源码仓库与发布检查

仓库已经包含 ShellCheck、Hadolint、Actionlint、单元测试、真实容器集成测试、双架构构建以及 Trivy
高危漏洞阻断。Cloudflare 的 Nginx 源站和 Shadowsocks 服务使用同一个扫描过的发布镜像。发布前执行：

```bash
make test
make build
make scan
make integration
make multiarch
```

`.github/workflows/ci.yml` 会在 push 和 pull request 时重复这些核心检查。
`.github/workflows/docker-publish.yml` 会在推送 `v*` 标签后，将 `linux/amd64` 和 `linux/arm64`
镜像发布到 GHCR，并生成 provenance 和 SBOM。完整发布步骤见 `RELEASING.md`。

项目使用 [MIT License](LICENSE)。

## 设计说明

Cloudflare 模式的数据路径：

```text
客户端
  -> Cloudflare Worker:443 (TLS + WebSocket)
  -> VPS Docker Nginx:8080 (路径 + Origin Token 校验)
  -> Shadowsocks Rust + v2ray-plugin:8388
  -> 目标网站
```

直连模式的数据路径：

```text
客户端
  -> VPS:8388 TCP/UDP
  -> Shadowsocks Rust
  -> 目标网站
```

Cloudflare Worker 的脚本、绑定和 `workers.dev` 路由使用 Cloudflare 官方 Workers API 管理；
WebSocket 请求由 Worker 的 `fetch()` 转发。相关官方资料：

- [Workers Scripts API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/)
- [Workers API Token 权限](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)
- [Workers WebSockets](https://developers.cloudflare.com/workers/examples/websockets/)
- [Workers 自定义端口兼容标志](https://developers.cloudflare.com/workers/configuration/compatibility-flags/#allow-custom-ports)
- [Shadowsocks Rust Docker](https://github.com/shadowsocks/shadowsocks-rust/blob/master/README.md)
- [v2ray-plugin](https://github.com/shadowsocks/v2ray-plugin)

Cloudflare 免费网络并不保证一定改善所有中国大陆线路。安装后应分别在移动、联通、电信网络上测试，
保留直连模式作为排障和回退方案。
