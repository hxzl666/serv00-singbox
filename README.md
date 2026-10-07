# Serv00/Hostuno 多协议节点安装脚本

<div align="center">

![FreeBSD](https://img.shields.io/badge/FreeBSD-AB2B28?logo=freebsd&logoColor=white)
![Shell](https://img.shields.io/badge/Shell_Script-121011?logo=gnu-bash&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?logo=cloudflare&logoColor=white)
![Psiphon](https://img.shields.io/badge/Psiphon-1E90FF?logo=&logoColor=white)

**一键在 Serv00/Hostuno 免费服务器上部署多协议代理节点**

**支持主节点 WARP + Psiphon 赛风出站，解锁流媒体；副节点多出口平行隔离**

</div>

---

## 📋 项目简介

这是一个专为 **Serv00** 和 **Hostuno** 免费服务器设计的多协议代理节点一键安装脚本。脚本风格参考了 [甬哥(yonggekkk)](https://github.com/yonggekkk/sing-box-yg) 和 [老王(eooce)](https://github.com/eooce/Sing-box) 的优秀项目，整合优化后支持更多协议，全面兼容 FreeBSD 用户态环境（适配 20 进程配额、端口范围限制与端口冲突自愈）。

---

## ✨ 支持的协议

| 协议 | 状态 | 说明 |
|------|------|------|
| **Argo Tunnel** | ✅ 默认启用 | Cloudflare 隧道，支持临时/固定域名 |
| **VLESS-Reality** | ✅ 默认启用 | 最新 Reality 协议，安全性高 |
| **VMess-WS** | ✅ 默认启用 | 支持 WebSocket，可配合 CDN |
| **Trojan-WS** | ⚪ 可选 | Trojan over WebSocket |
| **Hysteria2** | ✅ 默认启用 | 基于 QUIC 的高速协议 |
| **TUIC v5** | ✅ 默认启用 | UDP 转发协议，延迟低 |
| **Shadowsocks-2022** | ⚪ 可选 | 最新 Shadowsocks 协议 |

---

## 🚀 一键安装 (Serv00 / Hostuno / CT8)

```bash
bash <(curl -Lks https://raw.githubusercontent.com/hxzl666/serv00-singbox/main/serv00_nodes.sh)
```

或者使用 wget:

```bash
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/hxzl666/serv00-singbox/main/serv00_nodes.sh)
```

**安装完成后，使用快捷命令 `sb` 即可快速进入菜单**

---

## 📦 支持平台

- **Serv00** - 波兰免费服务器 (serv00.net)
- **Hostuno** - Serv00 共享主机环境 (useruno.com)
- **CT8** - 另一个免费服务器 (ct8.pl)

---

## 🔧 功能特性

| 功能 | 说明 |
|------|------|
| 多协议支持 | 一键安装多达 7 种代理协议 |
| Argo 隧道 | 支持临时隧道和固定隧道切换 |
| **主节点出站管理** | 支持直连原生出站、**WARP 全局/分流出站**以及 **Psiphon 赛风全局/分流出站** |
| **Psiphon 赛风多出口** | 拥有独立 28+ 国家智能优选与副节点平行多出口实例（CZ/FI/GB/RO 等） |
| **免费节点池 / OpenRung** | 支持自定义代理出站多出口配置、端口复用、一键导入免费节点池并自动健康自愈 |
| 自动端口管理 | 自动申请与检测 TCP/UDP 端口，支持端口跨 IP 复用与冲突自愈 |
| Reality 支持 | 自动生成 Reality 密钥对 |
| 订阅链接 | 自动生成 Base64 订阅链接与自定义节点组合推送 |
| 多 IP 支持 | 自动检测多 IP 环境并按 IP 分流入站 |
| 哪吒探针 | 支持 v0 和 v1 版本 |
| 快捷命令 | 使用 `sb` 快速启动管理菜单 |

---

## 📋 菜单选项

| 选项 | 功能 | 说明 |
|:---:|------|------|
| **1** | 重新配置主节点协议 | 一键安装/重新配置 VLESS/Hy2/TUIC/VMess/Trojan/SS 等核心协议 |
| **2** | **主节点出站管理** | **切换直连出站 / WARP 全局与分流 / Psiphon 赛风全局与分流出站** |
| **3** | 主节点 Argo 隧道管理 | 切换 Cloudflare 临时隧道与 Token/JSON 固定隧道 |
| **4** | 查看主节点信息与链接 | 查看主节点配置、单节点 URI 与 Clash/Sing-box 订阅链接 |
| **5** | **赛风综合管理** | 赛风主服务启停、28 国智能优选、国家切换、测试与副节点组管理 |
| **6** | 自定义代理出站管理 | 自定义代理出站多出口配置、端口复用、一键添加免费节点池与 OpenRung |
| **7** | 自定义节点组合推送 | 勾选主节点与副节点组合，一键推送到 CF-Workers-SUB 远程订阅 |
| **8** | 查看全部节点信息总览 | 一览所有主节点与副节点（赛风多出口、代理出口）运行状态与端口 |
| **9** | 重启所有服务 | 端口检测与自愈、拉起副节点赛风实例、同步代理组与 sing-box 核心 |
| **10** | 端口冲突检测与重置 | 检测多 IP 端口占用，最小化换端口自愈或全量端口重分配 |
| **11** | 查看运行日志 | 查看 Sing-box 核心、Psiphon 赛风、Argo 隧道与系统日志 |
| **12** | 卸载删除主节点服务 | 停止服务并清理主节点配置 |
| **13** | 系统初始化与环境重置 | 彻底清理所有服务进程与工作目录，恢复纯净初始环境 |
| **0** | 退出脚本 | 退出交互菜单 |

---

## 💡 常见问题

### Q: 什么是主节点出站管理？如何使用赛风出站？

在 **菜单选项 2（主节点出站管理）** 中，可以为所有主节点（VLESS、Hysteria2、TUIC 等）设置流量出口：
1. **原生直连出站 (Direct)**：流量直接由服务器本机公网 IP 出站。
2. **WARP 全局出站 / 规则分流**：流量经 Cloudflare WARP 出站，分流模式下仅 Google/YouTube/Netflix/OpenAI 走 WARP。
3. **Psiphon 赛风全局出站**：所有主节点流量经本地 Psiphon SOCKS5 代理出站，享受赛风 28+ 国家出口。
4. **Psiphon 赛风规则分流**：仅 Google/YouTube/Netflix/OpenAI 走赛风出口，普通流量直连。

**提示**：副节点（已配置的赛风多出口副节点如 CZ/FI/GB/RO，以及自定义代理出站副节点）为独立平行系统，拥有专属入站端口与专属路由规则，切换主节点出站时副节点受到严格隔离保护，绝不受影响。

### Q: 赛风综合管理（选项 5）与主节点赛风出站有什么联系？

选项 5 负责 Psiphon 主服务的核心运维与国家切换：
- **查看当前出口 IP**：实时探测当前赛风出口 IP、国家与运营商。
- **智能优选出口国家**：多国并发探活，自动选出延迟最低、连通性最佳的出口。
- **手动切换出口国家**：支持 US、JP、SG、HK、GB、DE 等 28+ 个国家及 AUTO。
当主节点启用了赛风出站后，在此处切换国家，主节点的出口 IP 将同步切换至所选国家！

---

## ⚠️ 注意事项

1. **Serv00 风险提示**: 免费版 Serv00 使用代理脚本有被封号风险，收费版 Hostuno 无此问题
2. **端口限制**: 每个账号只能开放有限端口（通常 3-4 个）；Hostuno 用户态放行端口范围为 63001-65535
3. **不要混用脚本**: 请勿与其他 Serv00 脚本混用
4. **证书验证**: UDP 协议（Hy2/TUIC）需客户端关闭证书验证（设置 `insecure=true`）

---

## 🙏 致谢

- [yonggekkk/sing-box-yg](https://github.com/yonggekkk/sing-box-yg) - 甬哥 Sing-box 脚本
- [eooce/Sing-box](https://github.com/eooce/Sing-box) - 老王 Sing-box 脚本
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box) - Sing-box 核心

---

## 📄 免责声明

本项目仅供学习交流使用，请遵守当地法律法规。使用本脚本所产生的一切后果由使用者自行承担。
