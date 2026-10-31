# New-Suoha: Cloudflare Argo + Xray 一键全自动脚本

轻量、极速、开箱即用的多协议隧道穿透脚本。支持在主流 Linux 系统的 VPS 上一键并发部署 **VLESS-WS** 与 **Trojan-WS** 节点，通过 Cloudflare Argo 隧道实现穿透免开端口，同时矩阵式输出多组优选 CDN 域名与 443 TLS 节点，并由本地内置 HTTP 服务提供全自动化订阅及主流客户端导入配置。

---

## 致谢与致敬 (Acknowledgments)

本项目基于开源社区优秀成果二次开发与重构，在此特别鸣谢：

* **原版梭哈脚本**：感谢 [jwfst5088/suoha.sh](https://github.com/jwfst5088/suoha.sh) 开拓性的灵感启发与基础实现，经典梭哈模式为轻量化 Argo 部署奠定了极简实用的体验基础。
* **Cloudflare 优选节点提供方**：感谢社区与站长们无私维护并分享的高质量 Cloudflare 优选 CDN 域名（如 `cf.090227.xyz`、`cloudflare.182682.xyz` 等），极大改善了国内到 Cloudflare 边缘网络的延迟与连接质量。
* **XTLS 与 Cloudflare**：感谢 [XTLS/Xray-core](https://github.com/XTLS/Xray-core) 与 [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) 提供的底层开源技术支持。

---

## 核心特性

* **多系统支持**：原生适配 Debian、Ubuntu、CentOS、Fedora 及 Alpine Linux。
* **免提供域名**：默认提供 **梭哈模式 (Quick Tunnel)**，无需自有域名和证书，自动生成临时 `*.trycloudflare.com` 域名打通隧道。
* **固定隧道模式**：提供 **安装服务模式 (Named Tunnel)**，支持绑定托管在 Cloudflare 上的自定义二级域名，并注册 Systemd / OpenRC 开机常驻自启。
* **双协议并发**：单次部署同时启动 VLESS-WS 与 Trojan-WS 协议，由 Xray 内部 path/fallback 机制分流，无冗余进程与端口冲突。
* **矩阵式优选节点**：
* 自动为每个协议生成 **3 组优选域名**节点：
* `默认 Argo 域名`
* `cf.090227.xyz`
* `cloudflare.182682.xyz`


* 纯粹聚焦 **443 TLS** 标准节点，移除 80 端口无证书节点，保障链路加密与 CDN 握手稳定性。


* **本地极速订阅源**：
* 自动测算 VPS 外网真实 IP 并拉起微型 HTTP 订阅服务。
* 直接生成通用 Base64 订阅链接、`v2rayN / NekoBox` 专用 `sub://` 协议导入链接、以及可供 `Clash / Mihomo` 一键拉取的完整策略组配置。



---

## 一键运行命令

登录 VPS 终端（支持 root 用户），复制并执行以下命令即可启动交互菜单：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh)"

```

如果系统未预装 `curl`，可使用 `wget` 代替：

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/a6216abcd/newsuoha.sh/refs/heads/main/suoha.sh)"

```

---

## 使用指南

### 1. 梭哈模式 (推荐快速使用)

运行脚本后选择 `1`（或一路直接回车）：

1. 输入 Argo 连接网络类型（`4` 代表 IPv4，`6` 代表 IPv6，默认 `4`）。
2. 脚本自动下载并拉起对应架构的 `xray-core` 与 `cloudflared`。
3. 自动监听本地回环端口并打通 Cloudflare Quick Tunnel。
4. 终端直接打印：
* 全部 VLESS 与 Trojan 的 443 TLS 优选节点链接；
* 本地托管的 Base64 订阅链接；
* Clash / Clash.Meta / Mihomo 一键导入链接；
* 包含代理组与分流规则的完整 `clash.yaml` 本地直链。



> **提示**：梭哈模式生成的 Quick Tunnel 为临时隧道，VPS 重启或重新执行脚本时会自动刷新。

---

### 2. 安装服务模式 (长期托管)

如果拥有在 Cloudflare 托管的域名，并希望建立固定隧道：

1. 运行脚本选择 `2`。
2. 按照终端给出的 Cloudflare 登录链接在浏览器中授权域名。
3. 输入想要绑定的完整二级域名（例如 `sub.yourdomain.com`）。
4. 脚本将自动在云端注册 Named Tunnel 并完成 DNS 路由解析，同时将服务写入 Systemd（或 Alpine OpenRC）实现开机自启。
5. 服务安装完成后，随时在终端输入命令 `suoha` 即可呼出管理面板，进行启动、停止、重启、查看订阅或卸载操作。

---

## 节点与订阅导入说明

| 导入目标 | 说明 | 示例格式 / 文件 |
| --- | --- | --- |
| **v2rayN / NekoBox / Shadowrocket** | 复制终端输出的通用订阅 URL 直接粘贴添加订阅 | `http://<VPS_IP>:<端口>/sub.txt` |
| **快速调起客户端** | 复制并导入 `sub://` 深度链接 | `sub://http://<VPS_IP>:<端口>/sub.txt` |
| **Clash / Mihomo 一键配置** | 点击或导入配置链接直接拉取代理策略组 | `clash://install-config?url=http://<VPS_IP>:<端口>/clash.yaml` |
| **单节点导入** | 手动导入单条节点链接 | `vless://...` 或 `trojan://...` |

### 本地文件结构

* 节点文本列表：`/opt/suoha/nodes.txt`（梭哈模式在当前工作目录）
* Base64 订阅源：`/opt/suoha/sub.txt`
* Clash 完整配置：`/opt/suoha/clash.yaml`
* 汇总终端报告：`/opt/suoha/v2ray.txt`

---

## 卸载与清理

若需完全移除脚本运行环境及生成的服务：

* 重新运行脚本，在主菜单选择 `3. 卸载服务` 即可全自动停止进程、清除 Systemd 单元文件、清理本地配置文件及内置 HTTP 端口服务。

---

## 免责声明

本脚本仅供技术研究、网络协议分析及个人测试使用。请遵守当地法律法规，严禁将本项目用于任何违反网络安全及法律规定的用途。
