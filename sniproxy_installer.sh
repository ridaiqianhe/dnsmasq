#!/bin/bash

# SNIProxy & DNSMasq Interactive Installation Script v2.0
# Support for streaming services proxy configuration

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

# Safe service restart function
safe_restart_service(){
    local service_name=$1
    if [ -z "$service_name" ]; then
        echo -e "${BRed}Error: Service name cannot be empty${NC}"
        return 1
    fi
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        echo -e "${BRed}Error: Service ${service_name}.service does not exist${NC}"
        return 1
    fi
    
    echo -e "${BYellow}重启 ${service_name} 服务...${NC}"
    
    # Test configuration before restart
    if [ "$service_name" = "dnsmasq" ]; then
        if ! dnsmasq --test -C /etc/dnsmasq.conf 2>/dev/null; then
            echo -e "${BRed}✗ dnsmasq 配置文件有错误${NC}"
            echo -e "${BYellow}正在修复配置文件...${NC}"
            
            # Remove duplicate lines from config file
            if [ -f /etc/dnsmasq.conf ]; then
                # Create a backup
                cp /etc/dnsmasq.conf /etc/dnsmasq.conf.error.bak.$(date +%Y%m%d%H%M%S)
                
                # Remove duplicate lines while preserving order
                awk '!seen[$0]++' /etc/dnsmasq.conf > /tmp/dnsmasq.conf.clean
                mv /tmp/dnsmasq.conf.clean /etc/dnsmasq.conf
                
                # Test again
                if ! dnsmasq --test -C /etc/dnsmasq.conf 2>/dev/null; then
                    echo -e "${BRed}✗ 配置文件修复失败，请手动检查${NC}"
                    return 1
                fi
                echo -e "${BGreen}✓ 配置文件已修复${NC}"
            fi
        fi
    fi
    
    if systemctl restart "${service_name}"; then
        echo -e "${BGreen}✓ ${service_name} 服务重启成功${NC}"
        return 0
    else
        echo -e "${BRed}✗ ${service_name} 服务重启失败${NC}"
        echo -e "${BYellow}查看详细错误: journalctl -xeu ${service_name}.service${NC}"
        return 1
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
    echo -e "${BCyan}║${NC} ${BWhite}     SNIProxy & DNSMasq 流媒体代理安装工具 v2.0${NC}        ${BCyan}║${NC}"
    echo -e "${BCyan}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BCyan}║${NC} ${WHITE}系统: ${GREEN}$OS $VER${NC}                                          ${BCyan}║${NC}"
    echo -e "${BCyan}║${NC} ${WHITE}包管理器: ${GREEN}$PKG_MANAGER${NC}                                           ${BCyan}║${NC}"
    echo -e "${BCyan}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Get system status
get_status() {
    # Check SNIProxy status
    if systemctl is-active --quiet sniproxy; then
        SNIPROXY_STATUS="${BGreen}运行中${NC}"
    elif systemctl is-enabled --quiet sniproxy 2>/dev/null; then
        SNIPROXY_STATUS="${BYellow}已停止${NC}"
    else
        SNIPROXY_STATUS="${BRed}未安装${NC}"
    fi

    # Check DNSMasq status
    if systemctl is-active --quiet dnsmasq; then
        DNSMASQ_STATUS="${BGreen}运行中${NC}"
    elif systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
        DNSMASQ_STATUS="${BYellow}已停止${NC}"
    else
        DNSMASQ_STATUS="${BRed}未安装${NC}"
    fi

    # Get IP address
    SERVER_IP=$(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n1)
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
                apt install -y sniproxy
                ;;
            2)
                echo -e "${BGreen}从源码编译安装...${NC}"
                apt update
                apt install -y autotools-dev cdbs debhelper dh-autoreconf dpkg-dev \
                    gettext libev-dev libudns-dev pkg-config fakeroot devscripts \
                    autoconf build-essential

                cd /tmp
                wget https://github.com/dlundquist/sniproxy/archive/refs/tags/0.6.1.tar.gz
                tar -zxf 0.6.1.tar.gz
                cd sniproxy-0.6.1
                ./autogen.sh && dpkg-buildpackage
                dpkg -i ../sniproxy_*.deb
                cd /
                rm -rf /tmp/sniproxy*
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
        echo -e "${BGreen}安装编译依赖...${NC}"
        yum install -y epel-release
        yum install -y autoconf automake curl gettext-devel libev-devel \
            pcre-devel perl pkgconfig rpm-build udns-devel gcc-c++ make

        echo -e "${BGreen}从源码编译安装...${NC}"
        cd /tmp
        wget https://github.com/dlundquist/sniproxy/archive/refs/tags/0.6.1.tar.gz
        tar -zxf 0.6.1.tar.gz
        cd sniproxy-0.6.1
        ./autogen.sh && ./configure && make && make install
        cd /
        rm -rf /tmp/sniproxy*
    fi

    echo -e "${BGreen}SNIProxy 安装完成${NC}"
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

    # Create systemd service if not exists
    if [ ! -f /etc/systemd/system/sniproxy.service ] && [ ! -f /lib/systemd/system/sniproxy.service ]; then
        cat > /etc/systemd/system/sniproxy.service << 'EOF'
[Unit]
Description=SNI Proxy
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/sniproxy -c /etc/sniproxy.conf
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/sniproxy.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable sniproxy
    
    # Use safe restart function with error handling
    if safe_restart_service sniproxy; then
        echo -e "${BGreen}SNIProxy 配置完成${NC}"
    else
        echo -e "${BRed}SNIProxy 配置失败，请检查错误信息${NC}"
        return 1
    fi
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
        wget -q -O $DOMAINS_FILE https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/proxy-domains.txt || \
        curl -sL -o $DOMAINS_FILE https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/proxy-domains.txt
    fi

    # Generate clean dnsmasq config without duplicates
    cat > /etc/dnsmasq.conf << EOF
# DNSMasq Configuration
# Generated by SNIProxy Installer

port=53
domain-needed
bogus-priv
no-resolv
server=/cn/223.5.5.5
server=/cn/119.29.29.29
resolv-file=/etc/resolv.dnsmasq.conf
strict-order
no-hosts
listen-address=127.0.0.1,$SERVER_IP
cache-size=10000
log-queries
log-facility=/var/log/dnsmasq.log

# Streaming service domains
EOF

    # Add domains to config
    while IFS= read -r domain; do
        # Skip comments and empty lines
        [[ "$domain" =~ ^#.*$ ]] && continue
        [[ -z "$domain" ]] && continue
        echo "server=/$domain/$proxy_ip" >> /etc/dnsmasq.conf
    done < "$DOMAINS_FILE"

    systemctl enable dnsmasq
    
    # Use safe restart function with error handling
    if safe_restart_service dnsmasq; then
        echo -e "${BGreen}DNSMasq 配置完成${NC}"
    else
        echo -e "${BRed}DNSMasq 配置失败，请检查错误信息${NC}"
        return 1
    fi
}

# Show streaming services menu
show_streaming_menu() {
    echo -e "${BCyan}选择要代理的流媒体服务:${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BCyan}1)${NC}  全部服务 (默认)"
    echo -e "  ${BCyan}2)${NC}  Netflix"
    echo -e "  ${BCyan}3)${NC}  Disney+"
    echo -e "  ${BCyan}4)${NC}  HBO Max"
    echo -e "  ${BCyan}5)${NC}  Amazon Prime Video"
    echo -e "  ${BCyan}6)${NC}  YouTube"
    echo -e "  ${BCyan}7)${NC}  Hulu"
    echo -e "  ${BCyan}8)${NC}  日本媒体 (AbemaTV, DMM等)"
    echo -e "  ${BCyan}9)${NC}  台湾媒体 (KKTV, LineTV等)"
    echo -e "  ${BCyan}10)${NC} 香港媒体 (ViuTV, MyTVSuper等)"
    echo -e "  ${BCyan}11)${NC} AI平台 (OpenAI, Claude等)"
    echo -e "  ${BCyan}12)${NC} 自定义域名列表"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main menu
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
    echo -e "  ${BCyan}11)${NC} 卸载服务"
    echo -e "  ${BCyan}0)${NC}  退出"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Service control functions
start_services() {
    echo -e "${BGreen}启动服务...${NC}"
    systemctl start sniproxy 2>/dev/null && echo -e "${BGreen}SNIProxy 已启动${NC}" || echo -e "${BYellow}SNIProxy 启动失败或未安装${NC}"
    systemctl start dnsmasq 2>/dev/null && echo -e "${BGreen}DNSMasq 已启动${NC}" || echo -e "${BYellow}DNSMasq 启动失败或未安装${NC}"
}

stop_services() {
    echo -e "${BYellow}停止服务...${NC}"
    systemctl stop sniproxy 2>/dev/null && echo -e "${BGreen}SNIProxy 已停止${NC}" || echo -e "${BYellow}SNIProxy 未运行${NC}"
    systemctl stop dnsmasq 2>/dev/null && echo -e "${BGreen}DNSMasq 已停止${NC}" || echo -e "${BYellow}DNSMasq 未运行${NC}"
}

restart_services() {
    echo -e "${BGreen}重启服务...${NC}"
    
    # Restart sniproxy safely
    if systemctl list-unit-files | grep -q "^sniproxy.service"; then
        safe_restart_service sniproxy || echo -e "${BYellow}SNIProxy 重启失败${NC}"
    else
        echo -e "${BYellow}SNIProxy 服务未安装${NC}"
    fi
    
    # Restart dnsmasq safely
    if systemctl list-unit-files | grep -q "^dnsmasq.service"; then
        safe_restart_service dnsmasq || echo -e "${BYellow}DNSMasq 重启失败${NC}"
    else
        echo -e "${BYellow}DNSMasq 服务未安装${NC}"
    fi
}

# Show service status
show_status() {
    echo -e "${BCyan}服务状态:${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BWhite}SNIProxy:${NC} $SNIPROXY_STATUS"
    echo -e "${BWhite}DNSMasq:${NC}  $DNSMASQ_STATUS"
    echo -e "${BWhite}服务器 IP:${NC} ${BGreen}$SERVER_IP${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if systemctl is-active --quiet sniproxy 2>/dev/null; then
        echo -e "\n${BCyan}SNIProxy 端口监听:${NC}"
        # Try ss first, then netstat, with better error handling
        if command -v ss >/dev/null 2>&1; then
            ss -tlnp 2>/dev/null | grep -E ':80|:443' | grep -v grep || true
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tlnp 2>/dev/null | grep -E ':80|:443' | grep -v grep || true
        else
            echo -e "${BYellow}  端口 80/443 (检测工具未安装)${NC}"
        fi
    fi

    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        echo -e "\n${BCyan}DNSMasq 端口监听:${NC}"
        # Try ss first, then netstat, with better error handling
        if command -v ss >/dev/null 2>&1; then
            ss -tlnp 2>/dev/null | grep ':53' | grep -v grep || true
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tlnp 2>/dev/null | grep ':53' | grep -v grep || true
        else
            echo -e "${BYellow}  端口 53 (检测工具未安装)${NC}"
        fi
    fi

    echo ""  # Add empty line for better formatting
}

# View logs
view_logs() {
    echo -e "${BCyan}选择要查看的日志:${NC}"
    echo -e "  ${BCyan}1)${NC} SNIProxy HTTP 访问日志"
    echo -e "  ${BCyan}2)${NC} SNIProxy HTTPS 访问日志"
    echo -e "  ${BCyan}3)${NC} DNSMasq 查询日志"
    echo -e "  ${BCyan}4)${NC} 系统日志 (syslog)"
    read -p "请选择 [1-4]: " log_choice

    case $log_choice in
        1)
            if [ -f /var/log/sniproxy/http_access.log ]; then
                tail -n 50 /var/log/sniproxy/http_access.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        2)
            if [ -f /var/log/sniproxy/https_access.log ]; then
                tail -n 50 /var/log/sniproxy/https_access.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        3)
            if [ -f /var/log/dnsmasq.log ]; then
                tail -n 50 /var/log/dnsmasq.log
            else
                echo -e "${BYellow}日志文件不存在${NC}"
            fi
            ;;
        4)
            journalctl -xe -n 50
            ;;
        *)
            echo -e "${BRed}无效选择${NC}"
            ;;
    esac
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

# Test configuration
test_config() {
    echo -e "${BCyan}测试配置...${NC}"
    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Test DNS resolution
    echo -e "${BYellow}测试 DNS 解析:${NC}"
    for domain in netflix.com youtube.com disney.com; do
        result=$(dig +short $domain @127.0.0.1 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "  $domain -> ${BGreen}$result${NC}"
        else
            echo -e "  $domain -> ${BRed}解析失败${NC}"
        fi
    done

    # Test port connectivity
    echo -e "\n${BYellow}测试端口连接:${NC}"
    for port in 80 443; do
        if nc -zv 127.0.0.1 $port 2>/dev/null; then
            echo -e "  端口 $port -> ${BGreen}开放${NC}"
        else
            echo -e "  端口 $port -> ${BRed}关闭${NC}"
        fi
    done

    echo -e "${BWhite}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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

        read -p "请输入选项 [0-11]: " choice

        case $choice in
            1)
                install_sniproxy
                configure_sniproxy
                install_dnsmasq
                configure_dnsmasq
                start_services
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