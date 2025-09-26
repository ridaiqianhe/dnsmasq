#!/bin/bash

# SNIProxy & DNSMasq Interactive Installation Script v2.1
# Fixed display issues and improved error handling

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Bold colors
BRed='\033[1;31m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BBlue='\033[1;34m'
BPurple='\033[1;35m'
BCyan='\033[1;36m'
BWhite='\033[1;37m'

# Background colors
On_Yellow='\033[43m'
On_Cyan='\033[46m'
On_Green='\033[42m'
On_Red='\033[41m'

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${BRed}错误: 此脚本需要 root 权限运行${NC}"
        echo -e "${BYellow}请使用: sudo $0${NC}"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    else
        echo -e "${BRed}无法检测操作系统版本${NC}"
        exit 1
    fi

    # Check if it's Ubuntu/Debian based
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        PKG_MANAGER="apt"
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]] || [[ "$OS" == *"Fedora"* ]]; then
        PKG_MANAGER="yum"
    else
        echo -e "${BRed}不支持的操作系统: $OS${NC}"
        echo -e "${BYellow}此脚本仅支持 Ubuntu/Debian 或 CentOS/RHEL${NC}"
        exit 1
    fi
}

# Display banner
show_banner() {
    clear
    echo -e "${BCyan}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BCyan}║${NC} ${BWhite}     SNIProxy & DNSMasq 流媒体代理安装工具 v2.1${NC}        ${BCyan}║${NC}"
    echo -e "${BCyan}╠══════════════════════════════════════════════════════════╣${NC}"
    # Format OS and version display
    OS_DISPLAY=$(printf "%-20s" "$OS $VER")
    PKG_DISPLAY=$(printf "%-10s" "$PKG_MANAGER")
    echo -e "${BCyan}║${NC} ${WHITE}系统: ${GREEN}${OS_DISPLAY}${NC}                           ${BCyan}║${NC}"
    echo -e "${BCyan}║${NC} ${WHITE}包管理器: ${GREEN}${PKG_DISPLAY}${NC}                               ${BCyan}║${NC}"
    echo -e "${BCyan}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Get system status
get_status() {
    # Check SNIProxy status
    if systemctl is-active --quiet sniproxy 2>/dev/null; then
        SNIPROXY_STATUS="${BGreen}运行中${NC}"
    elif systemctl is-enabled --quiet sniproxy 2>/dev/null; then
        SNIPROXY_STATUS="${BYellow}已停止${NC}"
    else
        SNIPROXY_STATUS="${BRed}未安装${NC}"
    fi

    # Check DNSMasq status
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        DNSMASQ_STATUS="${BGreen}运行中${NC}"
    elif systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
        DNSMASQ_STATUS="${BYellow}已停止${NC}"
    else
        DNSMASQ_STATUS="${BRed}未安装${NC}"
    fi

    # Get IP address - improved detection
    SERVER_IP=""
    # Try different methods to get IP
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip -4 addr show | grep -oE 'inet [0-9.]+' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1)
    fi
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "无法检测")
    fi
}

# Install sniproxy from package or source
install_sniproxy() {
    echo -e "${BGreen}开始安装 SNIProxy...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        echo -e "${BYellow}选择安装方式:${NC}"
        echo -e "  ${BCyan}1)${NC} 从 APT 仓库安装 (推荐)"
        echo -e "  ${BCyan}2)${NC} 从源码编译安装"
        echo -e "  ${BCyan}3)${NC} 从预编译包安装"
        read -p "请选择 [1-3]: " install_choice

        case $install_choice in
            1)
                echo -e "${BGreen}从 APT 仓库安装...${NC}"
                apt update
                # Try to install sniproxy from apt, if fails, compile from source
                if ! apt install -y sniproxy 2>/dev/null; then
                    echo -e "${BYellow}APT 仓库中没有找到 sniproxy，自动切换到源码编译...${NC}"
                    install_sniproxy_from_source
                fi
                ;;
            2)
                install_sniproxy_from_source
                ;;
            3)
                echo -e "${BGreen}从预编译包安装...${NC}"
                echo -e "${BYellow}请确保 sniproxy 目录下有对应的 .deb 文件${NC}"
                read -p "输入 deb 文件路径: " deb_path
                if [ -f "$deb_path" ]; then
                    dpkg -i "$deb_path"
                    apt install -f -y
                else
                    echo -e "${BRed}文件不存在: $deb_path${NC}"
                    return 1
                fi
                ;;
            *)
                echo -e "${BRed}无效选择${NC}"
                return 1
                ;;
        esac
    else
        # For CentOS/RHEL
        install_sniproxy_from_source
    fi

    echo -e "${BGreen}SNIProxy 安装完成${NC}"
}

# Install sniproxy from source
install_sniproxy_from_source() {
    echo -e "${BGreen}从源码编译安装...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        apt update
        apt install -y autotools-dev cdbs debhelper dh-autoreconf dpkg-dev \
            gettext libev-dev libudns-dev pkg-config fakeroot devscripts \
            autoconf build-essential git
    else
        yum install -y epel-release
        yum install -y autoconf automake curl gettext-devel libev-devel \
            pcre-devel perl pkgconfig rpm-build udns-devel gcc-c++ make git
    fi

    cd /tmp
    rm -rf sniproxy*

    # Try to clone from git first
    if ! git clone https://github.com/dlundquist/sniproxy.git 2>/dev/null; then
        # Fallback to wget
        wget https://github.com/dlundquist/sniproxy/archive/refs/tags/0.6.1.tar.gz
        tar -zxf 0.6.1.tar.gz
        cd sniproxy-0.6.1
    else
        cd sniproxy
    fi

    ./autogen.sh
    ./configure
    make
    make install

    # Create binary link if not exists
    if [ ! -f /usr/sbin/sniproxy ]; then
        ln -s /usr/local/sbin/sniproxy /usr/sbin/sniproxy 2>/dev/null || true
    fi

    cd /
    rm -rf /tmp/sniproxy*
}

# Configure sniproxy
configure_sniproxy() {
    echo -e "${BGreen}配置 SNIProxy...${NC}"

    # Backup original config if exists
    if [ -f /etc/sniproxy.conf ]; then
        cp /etc/sniproxy.conf /etc/sniproxy.conf.bak.$(date +%Y%m%d%H%M%S)
    fi

    cat > /etc/sniproxy.conf << 'EOF'
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listen 80 {
    proto http
    table http_hosts
    access_log {
        filename /var/log/sniproxy/http_access.log
        priority notice
    }
}

listen 443 {
    proto tls
    table https_hosts
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

table http_hosts {
    .* *:80
}

table https_hosts {
    .* *:443
}
EOF

    # Create log directory
    mkdir -p /var/log/sniproxy
    touch /var/log/sniproxy/http_access.log
    touch /var/log/sniproxy/https_access.log
    chmod 755 /var/log/sniproxy

    # Create systemd service if not exists
    if [ ! -f /etc/systemd/system/sniproxy.service ] && [ ! -f /lib/systemd/system/sniproxy.service ]; then
        # Find sniproxy binary path
        SNIPROXY_BIN=$(which sniproxy 2>/dev/null || echo "/usr/sbin/sniproxy")

        cat > /etc/systemd/system/sniproxy.service << EOF
[Unit]
Description=SNI Proxy
After=network.target

[Service]
Type=forking
ExecStart=${SNIPROXY_BIN} -c /etc/sniproxy.conf
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/sniproxy.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable sniproxy
    systemctl restart sniproxy

    echo -e "${BGreen}SNIProxy 配置完成${NC}"
}

# Install dnsmasq
install_dnsmasq() {
    echo -e "${BGreen}开始安装 DNSMasq...${NC}"

    # Stop and disable systemd-resolved if running
    if systemctl is-active --quiet systemd-resolved; then
        echo -e "${BYellow}停止 systemd-resolved...${NC}"
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
    fi

    # Backup resolv.conf
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)
    fi

    # Install dnsmasq
    if [ "$PKG_MANAGER" = "apt" ]; then
        apt update
        apt install -y dnsmasq
    else
        yum install -y dnsmasq
    fi

    # Setup resolv.conf
    cat > /etc/resolv.dnsmasq.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
nameserver 119.29.29.29
EOF

    # Update system resolv.conf
    cat > /etc/resolv.conf << EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
options single-request-reopen
EOF

    # Prevent resolv.conf from being overwritten
    chattr +i /etc/resolv.conf

    echo -e "${BGreen}DNSMasq 安装完成${NC}"
}

# Configure dnsmasq with streaming domains
configure_dnsmasq() {
    echo -e "${BGreen}配置 DNSMasq...${NC}"

    # Get current server IP if not set
    if [ -z "$SERVER_IP" ]; then
        get_status
    fi

    read -p "输入 SNIProxy 服务器 IP 地址 [默认: $SERVER_IP]: " proxy_ip
    proxy_ip=${proxy_ip:-$SERVER_IP}

    # Backup original config
    if [ -f /etc/dnsmasq.conf ]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak.$(date +%Y%m%d%H%M%S)
    fi

    # Download proxy domains list
    echo -e "${BYellow}下载域名列表...${NC}"
    if [ -f proxy-domains.txt ]; then
        DOMAINS_FILE="proxy-domains.txt"
    else
        DOMAINS_FILE="/tmp/proxy-domains.txt"
        if ! wget -q -O $DOMAINS_FILE https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/proxy-domains.txt 2>/dev/null; then
            if ! curl -sL -o $DOMAINS_FILE https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/proxy-domains.txt 2>/dev/null; then
                echo -e "${BYellow}无法下载域名列表，使用默认配置${NC}"
                # Use a minimal default list
                cat > $DOMAINS_FILE << 'EOF'
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxext.com
nflxso.net
disney.com
disneyplus.com
disney-plus.net
dssott.com
hbo.com
hbomax.com
max.com
youtube.com
EOF
            fi
        fi
    fi

    # Generate dnsmasq config - Fixed version to prevent duplicates
    echo "# DNSMasq Configuration" > /etc/dnsmasq.conf
    echo "# Generated by SNIProxy Installer v2.1" >> /etc/dnsmasq.conf
    echo "" >> /etc/dnsmasq.conf
    echo "port=53" >> /etc/dnsmasq.conf
    echo "domain-needed" >> /etc/dnsmasq.conf
    echo "bogus-priv" >> /etc/dnsmasq.conf
    echo "no-resolv" >> /etc/dnsmasq.conf
    echo "resolv-file=/etc/resolv.dnsmasq.conf" >> /etc/dnsmasq.conf
    echo "strict-order" >> /etc/dnsmasq.conf
    echo "no-hosts" >> /etc/dnsmasq.conf
    echo "listen-address=127.0.0.1,$proxy_ip" >> /etc/dnsmasq.conf
    echo "cache-size=10000" >> /etc/dnsmasq.conf
    echo "log-queries" >> /etc/dnsmasq.conf
    echo "log-facility=/var/log/dnsmasq.log" >> /etc/dnsmasq.conf
    echo "" >> /etc/dnsmasq.conf
    echo "# China DNS servers" >> /etc/dnsmasq.conf
    echo "server=/cn/223.5.5.5" >> /etc/dnsmasq.conf
    echo "server=/cn/119.29.29.29" >> /etc/dnsmasq.conf
    echo "" >> /etc/dnsmasq.conf
    echo "# Streaming service domains" >> /etc/dnsmasq.conf

    # Add domains to config, avoiding duplicates
    declare -A seen_domains
    while IFS= read -r domain; do
        # Skip comments and empty lines
        [[ "$domain" =~ ^#.*$ ]] && continue
        [[ -z "$domain" ]] && continue
        # Skip if we've already seen this domain
        [[ "${seen_domains[$domain]}" == "1" ]] && continue
        seen_domains[$domain]=1
        echo "server=/$domain/$proxy_ip" >> /etc/dnsmasq.conf
    done < "$DOMAINS_FILE"

    # Create log file
    touch /var/log/dnsmasq.log
    chmod 644 /var/log/dnsmasq.log

    systemctl enable dnsmasq
    systemctl restart dnsmasq

    echo -e "${BGreen}DNSMasq 配置完成${NC}"
}

# Show main menu
show_menu() {
    echo -e "${BCyan}请选择操作:${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BCyan}1)${NC}  完整安装 (SNIProxy + DNSMasq)"
    echo -e "  ${BCyan}2)${NC}  仅安装 SNIProxy"
    echo -e "  ${BCyan}3)${NC}  仅安装 DNSMasq"
    echo -e "  ${BCyan}4)${NC}  配置 SNIProxy"
    echo -e "  ${BCyan}5)${NC}  配置 DNSMasq"
    echo -e "  ${BCyan}6)${NC}  启动服务"
    echo -e "  ${BCyan}7)${NC}  停止服务"
    echo -e "  ${BCyan}8)${NC}  重启服务"
    echo -e "  ${BCyan}9)${NC}  查看服务状态"
    echo -e "  ${BCyan}10)${NC} 查看日志"
    echo -e "  ${BCyan}11)${NC} 测试配置"
    echo -e "  ${BCyan}12)${NC} 卸载服务"
    echo -e "  ${BCyan}0)${NC}  退出"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Service control functions
start_services() {
    echo -e "${BGreen}启动服务...${NC}"

    # Start SNIProxy
    if systemctl start sniproxy 2>/dev/null; then
        echo -e "${BGreen}✓ SNIProxy 已启动${NC}"
    else
        echo -e "${BYellow}✗ SNIProxy 启动失败或未安装${NC}"
    fi

    # Start DNSMasq
    if systemctl start dnsmasq 2>/dev/null; then
        echo -e "${BGreen}✓ DNSMasq 已启动${NC}"
    else
        echo -e "${BYellow}✗ DNSMasq 启动失败或未安装${NC}"
    fi
}

stop_services() {
    echo -e "${BYellow}停止服务...${NC}"

    # Stop SNIProxy
    if systemctl stop sniproxy 2>/dev/null; then
        echo -e "${BGreen}✓ SNIProxy 已停止${NC}"
    else
        echo -e "${BYellow}✗ SNIProxy 未运行${NC}"
    fi

    # Stop DNSMasq
    if systemctl stop dnsmasq 2>/dev/null; then
        echo -e "${BGreen}✓ DNSMasq 已停止${NC}"
    else
        echo -e "${BYellow}✗ DNSMasq 未运行${NC}"
    fi
}

restart_services() {
    echo -e "${BGreen}重启服务...${NC}"

    # Restart SNIProxy
    if systemctl restart sniproxy 2>/dev/null; then
        echo -e "${BGreen}✓ SNIProxy 已重启${NC}"
    else
        echo -e "${BYellow}✗ SNIProxy 重启失败或未安装${NC}"
    fi

    # Restart DNSMasq
    if systemctl restart dnsmasq 2>/dev/null; then
        echo -e "${BGreen}✓ DNSMasq 已重启${NC}"
    else
        echo -e "${BYellow}✗ DNSMasq 重启失败或未安装${NC}"
    fi
}

# Show service status - Fixed version
show_status() {
    echo -e "${BCyan}服务状态:${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}SNIProxy:${NC} $SNIPROXY_STATUS"
    echo -e "${BWhite}DNSMasq:${NC}  $DNSMASQ_STATUS"
    echo -e "${BWhite}服务器 IP:${NC} ${BGreen}$SERVER_IP${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Check SNIProxy ports
    if systemctl is-active --quiet sniproxy 2>/dev/null; then
        echo ""
        echo -e "${BCyan}SNIProxy 端口监听:${NC}"

        # Check port 80
        if lsof -i:80 -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo -e "  ${BGreen}✓${NC} HTTP  端口 80  - 正常"
        else
            echo -e "  ${BRed}✗${NC} HTTP  端口 80  - 未监听"
        fi

        # Check port 443
        if lsof -i:443 -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo -e "  ${BGreen}✓${NC} HTTPS 端口 443 - 正常"
        else
            echo -e "  ${BRed}✗${NC} HTTPS 端口 443 - 未监听"
        fi
    fi

    # Check DNSMasq port
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        echo ""
        echo -e "${BCyan}DNSMasq 端口监听:${NC}"

        # Check port 53
        if lsof -i:53 -sTCP:LISTEN -t >/dev/null 2>&1 || lsof -i:53 -sUDP:Idle -t >/dev/null 2>&1; then
            echo -e "  ${BGreen}✓${NC} DNS 端口 53 - 正常"
        else
            echo -e "  ${BRed}✗${NC} DNS 端口 53 - 未监听"
        fi
    fi

    echo ""
}

# View logs
view_logs() {
    echo -e "${BCyan}选择要查看的日志:${NC}"
    echo -e "  ${BCyan}1)${NC} SNIProxy HTTP 访问日志"
    echo -e "  ${BCyan}2)${NC} SNIProxy HTTPS 访问日志"
    echo -e "  ${BCyan}3)${NC} DNSMasq 查询日志"
    echo -e "  ${BCyan}4)${NC} 系统日志 (syslog)"
    echo -e "  ${BCyan}5)${NC} 实时监控所有日志"
    read -p "请选择 [1-5]: " log_choice

    case $log_choice in
        1)
            if [ -f /var/log/sniproxy/http_access.log ]; then
                echo -e "${BCyan}最近的 HTTP 访问记录:${NC}"
                tail -n 50 /var/log/sniproxy/http_access.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        2)
            if [ -f /var/log/sniproxy/https_access.log ]; then
                echo -e "${BCyan}最近的 HTTPS 访问记录:${NC}"
                tail -n 50 /var/log/sniproxy/https_access.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        3)
            if [ -f /var/log/dnsmasq.log ]; then
                echo -e "${BCyan}最近的 DNS 查询记录:${NC}"
                tail -n 50 /var/log/dnsmasq.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        4)
            echo -e "${BCyan}系统日志:${NC}"
            journalctl -xe -n 50
            ;;
        5)
            echo -e "${BCyan}实时监控日志 (按 Ctrl+C 退出):${NC}"
            tail -f /var/log/sniproxy/*.log /var/log/dnsmasq.log 2>/dev/null
            ;;
        *)
            echo -e "${BRed}无效选择${NC}"
            ;;
    esac
}

# Test configuration
test_config() {
    echo -e "${BCyan}测试配置...${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Check if services are running
    echo -e "${BYellow}1. 服务运行状态:${NC}"
    if systemctl is-active --quiet sniproxy 2>/dev/null; then
        echo -e "   SNIProxy: ${BGreen}✓ 运行中${NC}"
    else
        echo -e "   SNIProxy: ${BRed}✗ 未运行${NC}"
    fi

    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        echo -e "   DNSMasq:  ${BGreen}✓ 运行中${NC}"
    else
        echo -e "   DNSMasq:  ${BRed}✗ 未运行${NC}"
    fi

    # Test DNS resolution
    echo ""
    echo -e "${BYellow}2. 测试 DNS 解析:${NC}"
    test_domains=("netflix.com" "youtube.com" "disney.com")

    for domain in "${test_domains[@]}"; do
        result=$(dig +short $domain @127.0.0.1 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "   $domain -> ${BGreen}$result${NC}"
        else
            echo -e "   $domain -> ${BRed}解析失败${NC}"
        fi
    done

    # Test port connectivity
    echo ""
    echo -e "${BYellow}3. 测试端口连接:${NC}"

    # Install nc if not available
    if ! command -v nc >/dev/null 2>&1; then
        echo -e "   ${BYellow}正在安装 netcat...${NC}"
        if [ "$PKG_MANAGER" = "apt" ]; then
            apt install -y netcat-openbsd 2>/dev/null || apt install -y netcat 2>/dev/null
        else
            yum install -y nc 2>/dev/null
        fi
    fi

    for port in 80 443 53; do
        if timeout 1 nc -zv 127.0.0.1 $port >/dev/null 2>&1; then
            case $port in
                80)  echo -e "   HTTP  (80):  ${BGreen}✓ 开放${NC}" ;;
                443) echo -e "   HTTPS (443): ${BGreen}✓ 开放${NC}" ;;
                53)  echo -e "   DNS   (53):  ${BGreen}✓ 开放${NC}" ;;
            esac
        else
            case $port in
                80)  echo -e "   HTTP  (80):  ${BRed}✗ 关闭${NC}" ;;
                443) echo -e "   HTTPS (443): ${BRed}✗ 关闭${NC}" ;;
                53)  echo -e "   DNS   (53):  ${BRed}✗ 关闭${NC}" ;;
            esac
        fi
    done

    # Test external connectivity
    echo ""
    echo -e "${BYellow}4. 测试外部连接:${NC}"
    if curl -s -o /dev/null -w "%{http_code}" https://www.netflix.com --connect-timeout 5 | grep -q "200\|301\|302"; then
        echo -e "   Netflix: ${BGreen}✓ 可访问${NC}"
    else
        echo -e "   Netflix: ${BRed}✗ 无法访问${NC}"
    fi

    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Uninstall services
uninstall_services() {
    echo -e "${BRed}警告: 这将卸载 SNIProxy 和 DNSMasq${NC}"
    read -p "确定要继续吗? [y/N]: " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BYellow}卸载服务...${NC}"

        # Stop services
        systemctl stop sniproxy 2>/dev/null
        systemctl stop dnsmasq 2>/dev/null

        # Disable services
        systemctl disable sniproxy 2>/dev/null
        systemctl disable dnsmasq 2>/dev/null

        # Remove packages
        if [ "$PKG_MANAGER" = "apt" ]; then
            apt remove -y sniproxy dnsmasq
            apt autoremove -y
        else
            yum remove -y sniproxy dnsmasq
        fi

        # Remove config files
        rm -f /etc/sniproxy.conf
        rm -f /etc/dnsmasq.conf
        rm -rf /var/log/sniproxy

        # Restore resolv.conf
        chattr -i /etc/resolv.conf
        if [ -f /etc/resolv.conf.bak.* ]; then
            latest_backup=$(ls -t /etc/resolv.conf.bak.* | head -1)
            cp $latest_backup /etc/resolv.conf
        fi

        # Re-enable systemd-resolved if available
        if systemctl list-unit-files | grep -q systemd-resolved; then
            systemctl enable systemd-resolved
            systemctl start systemd-resolved
        fi

        echo -e "${BGreen}卸载完成${NC}"
    else
        echo -e "${BYellow}操作已取消${NC}"
    fi
}

# Main program
main() {
    check_root
    detect_os

    while true; do
        show_banner
        get_status
        show_status
        echo ""
        show_menu

        read -p "请输入选项 [0-12]: " choice

        case $choice in
            1)
                install_sniproxy
                configure_sniproxy
                install_dnsmasq
                configure_dnsmasq
                start_services
                sleep 2
                test_config
                echo -e "${BGreen}完整安装完成！${NC}"
                echo -e "${BYellow}请将客户端 DNS 设置为: ${BGreen}$SERVER_IP${NC}"
                ;;
            2)
                install_sniproxy
                configure_sniproxy
                ;;
            3)
                install_dnsmasq
                configure_dnsmasq
                ;;
            4)
                configure_sniproxy
                ;;
            5)
                configure_dnsmasq
                ;;
            6)
                start_services
                ;;
            7)
                stop_services
                ;;
            8)
                restart_services
                ;;
            9)
                clear
                show_banner
                get_status
                show_status
                ;;
            10)
                view_logs
                ;;
            11)
                test_config
                ;;
            12)
                uninstall_services
                ;;
            0)
                echo -e "${BGreen}感谢使用！再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${BRed}无效的选项，请重新选择${NC}"
                ;;
        esac

        echo ""
        read -p "按 Enter 键继续..."
    done
}

# Run main program
main