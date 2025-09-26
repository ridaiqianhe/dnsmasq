# SNIProxy & DNSMasq 流媒体代理解锁工具

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS-blue)](https://github.com)
[![Version](https://img.shields.io/badge/Version-2.0-green)](https://github.com)

一个强大的流媒体代理解锁工具，通过 SNIProxy 和 DNSMasq 实现对各种流媒体服务的解锁访问。支持 Netflix、Disney+、HBO、YouTube、AI 平台等 550+ 个流媒体域名。

## 🌟 主要特性

- 🚀 **一键部署**：交互式安装脚本，自动配置所有组件
- 📦 **包管理支持**：优先使用 apt/yum 包管理器安装
- 🎯 **全面覆盖**：支持 550+ 个流媒体域名，涵盖全球主要服务
- 🎨 **友好界面**：彩色终端界面，实时状态显示
- 🔧 **灵活配置**：支持自定义域名列表和独立组件管理
- 📊 **状态监控**：实时查看服务状态和访问日志
- 🛡️ **安全可靠**：自动备份配置，支持完整卸载

## 📋 系统要求

- **操作系统**：Ubuntu 18.04+, Debian 9+, CentOS 7+
- **权限要求**：root 或 sudo 权限
- **网络要求**：需要公网 IP 地址
- **端口要求**：80 (HTTP), 443 (HTTPS), 53 (DNS)

## 🚀 快速开始

### 一键安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/dnsmasq.git
cd dnsmasq

# 添加执行权限
chmod +x sniproxy_installer.sh

# 运行安装脚本
sudo ./sniproxy_installer.sh
```

### 交互式菜单

运行脚本后，您将看到以下菜单选项：

```
╔══════════════════════════════════════════════════════════╗
║      SNIProxy & DNSMasq 流媒体代理安装工具 v2.0         ║
╠══════════════════════════════════════════════════════════╣
║  系统: Ubuntu 20.04                                      ║
║  包管理器: apt                                           ║
╚══════════════════════════════════════════════════════════╝

请选择操作:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1)  完整安装 (SNIProxy + DNSMasq)
  2)  仅安装 SNIProxy
  3)  仅安装 DNSMasq
  4)  配置 SNIProxy
  5)  配置 DNSMasq
  6)  启动服务
  7)  停止服务
  8)  重启服务
  9)  查看服务状态
  10) 查看日志
  11) 卸载服务
  0)  退出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 🎬 支持的流媒体服务

### 视频流媒体
- **全球平台**：Netflix, Disney+, HBO Max, Amazon Prime Video, Hulu, YouTube
- **亚洲平台**：
  - 🇯🇵 日本：AbemaTV, DMM, NHK, Hulu JP, TVer, WOWOW
  - 🇹🇼 台湾：KKTV, LineTV, 4GTV, MyVideo, CatchPlay, Bahamut
  - 🇭🇰 香港：ViuTV, MyTVSuper, NowTV, TVB
  - 🇰🇷 韩国：Wavve, Tving, CoupangPlay, KBS, JTBC
  - 🇸🇬 东南亚：MeWatch, TrueID, AIS Play, Sooka

### AI 平台
- OpenAI (ChatGPT, GPT-4, DALL-E, Sora)
- Anthropic (Claude)
- Google (Gemini, Bard)
- Microsoft Copilot

### 其他服务
- 音乐：Spotify, Apple Music, YouTube Music
- 体育：NBA, DAZN, ESPN, F1TV
- 社交：TikTok, Instagram
- 游戏：Steam
- 其他：iQiyi, BiliBili

完整域名列表请查看 [proxy-domains.txt](proxy-domains.txt)

## 📁 项目结构

```
dnsmasq/
├── sniproxy_installer.sh    # 主安装脚本
├── dnsmasq_sniproxy.sh     # 传统安装脚本（兼容旧版）
├── proxy-domains.txt        # 流媒体域名列表（550+域名）
├── sniproxy/               # SNIProxy 预编译包
│   ├── *.rpm              # CentOS/RHEL 包
│   └── *.deb              # Ubuntu/Debian 包
└── README.md              # 本文档
```

## 🔧 配置说明

### DNSMasq 配置

安装后，DNSMasq 会自动配置为将流媒体域名解析到 SNIProxy 服务器。主要配置文件位于：

- 配置文件：`/etc/dnsmasq.conf`
- 上游 DNS：`/etc/resolv.dnsmasq.conf`
- 日志文件：`/var/log/dnsmasq.log`

### SNIProxy 配置

SNIProxy 监听 80 和 443 端口，透明代理 HTTP/HTTPS 流量。主要配置文件位于：

- 配置文件：`/etc/sniproxy.conf`
- 访问日志：`/var/log/sniproxy/`

## 🖥️ 客户端配置

### 方法一：修改 DNS 设置

将设备的 DNS 服务器设置为安装了本工具的服务器 IP 地址。

#### Windows
```
网络和 Internet 设置 -> 更改适配器选项 -> 属性 -> IPv4 -> DNS 服务器
```

#### macOS
```
系统偏好设置 -> 网络 -> 高级 -> DNS -> 添加服务器 IP
```

#### Linux
编辑 `/etc/resolv.conf`：
```bash
nameserver YOUR_SERVER_IP
```

### 方法二：路由器配置

在路由器的 DHCP/DNS 设置中，将 DNS 服务器设置为本工具的服务器 IP，所有连接到该路由器的设备都会自动使用代理。

## 🔍 故障排查

### 检查服务状态
```bash
sudo ./sniproxy_installer.sh
# 选择选项 9 查看服务状态
```

### 测试 DNS 解析
```bash
# 测试 DNS 是否正常工作
dig netflix.com @YOUR_SERVER_IP

# 测试连通性
curl -I https://netflix.com
```

### 查看日志
```bash
# SNIProxy 日志
tail -f /var/log/sniproxy/https_access.log

# DNSMasq 日志
tail -f /var/log/dnsmasq.log
```

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   sudo netstat -tlnp | grep :80
   sudo netstat -tlnp | grep :443
   sudo netstat -tlnp | grep :53
   ```

2. **systemd-resolved 冲突**
   脚本会自动处理，但如需手动处理：
   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

3. **防火墙设置**
   ```bash
   # Ubuntu/Debian
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 53

   # CentOS
   sudo firewall-cmd --permanent --add-service=http
   sudo firewall-cmd --permanent --add-service=https
   sudo firewall-cmd --permanent --add-service=dns
   sudo firewall-cmd --reload
   ```

## 🔄 更新域名列表

如需更新域名列表，可以编辑 `proxy-domains.txt` 文件，然后重新配置 DNSMasq：

```bash
sudo ./sniproxy_installer.sh
# 选择选项 5 (配置 DNSMasq)
```

## 📝 高级配置

### 自定义上游 DNS

编辑 `/etc/resolv.dnsmasq.conf`：
```bash
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5  # 阿里 DNS
nameserver 119.29.29.29  # DNSPod
```

### 添加自定义域名

编辑 `/etc/dnsmasq.conf`，添加：
```bash
server=/example.com/YOUR_PROXY_IP
```

### 性能优化

编辑 `/etc/sniproxy.conf`，调整工作进程数：
```conf
user daemon
pidfile /var/run/sniproxy.pid

# 增加工作进程数以提高并发性能
workers 4
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

如果您发现新的流媒体域名需要添加，请：
1. Fork 本项目
2. 编辑 `proxy-domains.txt` 添加域名
3. 提交 Pull Request

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [SNIProxy](https://github.com/dlundquist/sniproxy) - 透明 SSL 代理
- [DNSMasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) - 轻量级 DNS 服务器
- 原项目作者 [@myxuchangbin](https://github.com/myxuchangbin)

## ⚠️ 免责声明

本工具仅供学习和研究使用，请遵守当地法律法规和服务条款。使用本工具所产生的任何后果由用户自行承担，作者不承担任何责任。

## 📮 联系方式

- GitHub Issues: [提交问题](https://github.com/yourusername/dnsmasq/issues)
- 邮箱: your-email@example.com

---

**如果这个项目对您有帮助，请给一个 ⭐ Star！**