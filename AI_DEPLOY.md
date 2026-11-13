# 交给 AI 的 VPS 部署说明

当用户要求把本项目部署到新 VPS 时，AI 应遵循本清单。

## 先向用户确认

修改 VPS 前确认：

1. 目标 VPS，以及已经可用且具备 root 权限的 SSH 会话。
2. 部署模式：`cloudflare` 或 `direct`。
3. 使用默认端口和自动生成密码，还是使用用户指定值。
4. Cloudflare 模式下，`cloudflare-vps-prep.json` 上传到 VPS 后的路径。

不要要求用户在公开对话中粘贴 SSH 私钥、Cloudflare API Token 或生成的 `ss://` 链接。不要修改或删除
当前正在使用的 SSH 防火墙规则。

## 下载并校验 Release

不要直接执行 `raw/main/vps-ss.sh`。下载 GitHub 最新 Release 的文件并验证安装脚本：

```bash
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/vps-ss.sh
curl -fLO https://github.com/liqiuh/vps-ss-docker/releases/latest/download/SHA256SUMS
grep ' vps-ss.sh$' SHA256SUMS | sha256sum -c -
chmod +x vps-ss.sh
```

仅支持 Ubuntu 和 Debian，安装脚本需要 root 权限。

## 防火墙要求

本机防火墙和云厂商安全组都必须保留当前 SSH TCP 端口：

- Cloudflare 模式：允许入站 TCP `8080` 或指定的 `ORIGIN_PORT`。不要开放该端口的 UDP；VPS 不需要入站 TCP `443`。
- 直连模式：同时允许入站 TCP 和 UDP `8388`，或指定的 `DIRECT_PORT`。
- 如果限制出站流量，允许 DNS 和出站 TCP `80/443`。

脚本会修改已经启用的 UFW 或 firewalld。云厂商安全组及自定义 nftables/iptables 规则必须另外配置。

## 安装

默认直连模式：

```bash
sudo ./vps-ss.sh install direct
```

指定直连端口和密码：

```bash
DIRECT_PORT=24443 SS_PASSWORD='custom-pass_123!' \
  sudo -E ./vps-ss.sh install direct
```

默认 Cloudflare 模式：

```bash
sudo ./vps-ss.sh install cloudflare /root/cloudflare-vps-prep.json
```

指定 Cloudflare 回源端口和密码：

```bash
ORIGIN_PORT=8880 SS_PASSWORD='custom-pass_123!' \
  sudo -E ./vps-ss.sh install cloudflare /root/cloudflare-vps-prep.json
```

密码必须为 8-128 位，并且只能使用：

```text
A-Z a-z 0-9 . _ ~ ! @ % + = , : / -
```

不设置 `SS_PASSWORD` 时，脚本会生成强随机密码。人工指定密码时优先使用交互菜单的隐藏输入，避免密码写入
shell 历史。

## 验证与交付

运行：

```bash
vps-ss status
vps-ss info
```

只有当用户准备导入客户端配置时，才运行以下命令之一：

```bash
vps-ss link
vps-ss clash
```

这两个命令会显示 Shadowsocks 密码。输出属于敏感信息，不得发布到公开对话或日志中。
