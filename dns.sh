#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root权限运行!" && exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="/var/log/dns-proxy"
DNSMASQ_CONFIG="/etc/dnsmasq.conf"
SNIPROXY_CONFIG="/etc/sniproxy.conf"

check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "[${red}Error${plain}] 无法检测操作系统版本!"
        exit 1
    fi

    case $OS in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update"
            ;;
        centos|rhel|fedora)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update"
            ;;
        *)
            echo -e "[${red}Error${plain}] 不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

check_ports() {
    local ports=(53 80 443)
    local occupied=()

    for port in "${ports[@]}"; do
        if command -v lsof > /dev/null; then
            if lsof -i :$port > /dev/null 2>&1; then
                occupied+=($port)
            fi
        elif command -v ss > /dev/null; then
            if ss -tuln | grep -q ":$port "; then
                occupied+=($port)
            fi
        fi
    done

    if [ ${#occupied[@]} -gt 0 ]; then
        echo -e "[${yellow}Warning${plain}] 以下端口被占用: ${occupied[@]}"
        echo -e "是否尝试停止占用的服务? [y/N]"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            stop_conflicting_services
        fi
    fi
}

stop_conflicting_services() {
    # 停止已知服务
    local services=("systemd-resolved" "bind9" "named" "apache2" "nginx" "httpd")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo -e "[${green}Info${plain}] 停止服务: $service"
            systemctl stop $service
            systemctl disable $service 2>/dev/null
        fi
    done

    # 强制杀死残留的sniproxy进程
    echo -e "[${green}Info${plain}] 清理残留进程..."
    pkill -9 sniproxy 2>/dev/null

    # 等待端口释放
    sleep 2
}

get_external_ip() {
    local ip_services=(
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me"
        "https://ip.sb"
    )

    for service in "${ip_services[@]}"; do
        external_ip=$(curl -s -4 --connect-timeout 5 $service)
        if [[ $external_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${external_ip}"
            return 0
        fi
    done

    # 获取本地IP作为备用
    local_ip=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
    if [ -n "$local_ip" ]; then
        echo "${local_ip}"
        return 0
    fi

    echo -e "[${red}Error${plain}] 无法获取IP地址"
    exit 1
}

install_dependencies() {
    echo -e "[${green}Info${plain}] 安装依赖包..."

    # 修复DNS解析
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf

    $PKG_UPDATE > /dev/null 2>&1

    local packages=("curl" "wget" "lsof" "iptables")

    for pkg in "${packages[@]}"; do
        if ! command -v $pkg > /dev/null; then
            echo -e "[${green}Info${plain}] 安装 $pkg..."
            $PKG_MANAGER install -y $pkg > /dev/null 2>&1
        fi
    done
}

install_dnsmasq() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 dnsmasq..."
    echo -e "[${green}Info${plain}] 服务器IP: ${external_ip}"

    $PKG_MANAGER install -y dnsmasq > /dev/null 2>&1

    echo -e "[${green}Info${plain}] 配置 dnsmasq..."

    cat > $DNSMASQ_CONFIG <<EOF
# 基础配置
user=nobody
no-resolv
no-poll
expand-hosts
listen-address=127.0.0.1,$external_ip
bind-interfaces
cache-size=10000
min-cache-ttl=300

# 上游DNS服务器
server=8.8.8.8
server=8.8.4.4
server=1.1.1.1
server=1.0.0.1

# 国内DNS（用于国内域名）
server=/cn/223.5.5.5
server=/cn/119.29.29.29

# 日志配置
log-facility=/var/log/dnsmasq.log

# 流媒体域名解析到本服务器
address=/netflix.com/$external_ip
address=/netflix.net/$external_ip
address=/nflximg.com/$external_ip
address=/nflximg.net/$external_ip
address=/nflxvideo.net/$external_ip
address=/nflxext.com/$external_ip
address=/nflxso.net/$external_ip

address=/disneyplus.com/$external_ip
address=/disney-plus.net/$external_ip
address=/dssott.com/$external_ip
address=/bamgrid.com/$external_ip
address=/disneystreaming.com/$external_ip

address=/youtube.com/$external_ip
address=/googlevideo.com/$external_ip
address=/ytimg.com/$external_ip
address=/ggpht.com/$external_ip
address=/youtubei.googleapis.com/$external_ip

address=/amazonvideo.com/$external_ip
address=/primevideo.com/$external_ip
address=/aiv-cdn.net/$external_ip
address=/aiv-delivery.net/$external_ip
address=/pv-cdn.net/$external_ip

address=/hbo.com/$external_ip
address=/hbomax.com/$external_ip
address=/hbogo.com/$external_ip
address=/hbonow.com/$external_ip
address=/max.com/$external_ip
EOF

    mkdir -p $LOG_DIR
    touch /var/log/dnsmasq.log
    chown nobody:nogroup /var/log/dnsmasq.log

    systemctl enable dnsmasq
    systemctl restart dnsmasq

    if systemctl is-active --quiet dnsmasq; then
        echo -e "[${green}Success${plain}] dnsmasq 安装并启动成功"
    else
        echo -e "[${red}Error${plain}] dnsmasq 启动失败"
        systemctl status dnsmasq --no-pager
    fi
}

install_sniproxy() {
    echo -e "[${green}Info${plain}] 安装 sniproxy..."

    # 彻底清理所有sniproxy进程
    echo -e "[${green}Info${plain}] 清理残留进程..."
    systemctl stop sniproxy 2>/dev/null
    systemctl kill -s KILL sniproxy 2>/dev/null

    # 查找并杀死所有sniproxy进程
    for pid in $(ps aux | grep '[s]niproxy' | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null
    done

    pkill -9 sniproxy 2>/dev/null
    killall -9 sniproxy 2>/dev/null

    # 清理PID文件
    rm -f /var/run/sniproxy.pid

    # 等待进程完全退出
    sleep 2

    # 安装sniproxy
    $PKG_MANAGER install -y sniproxy > /dev/null 2>&1

    echo -e "[${green}Info${plain}] 配置 sniproxy..."

    # 使用简化且稳定的配置
    cat > $SNIPROXY_CONFIG <<'EOF'
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listener 0.0.0.0:80 {
    proto http
    table all_hosts
}

listener 0.0.0.0:443 {
    proto tls
    table all_hosts
}

table all_hosts {
    .* *
}
EOF

    # 修复systemd服务文件（如果需要）
    if [ -f /lib/systemd/system/sniproxy.service ]; then
        # 备份原文件
        cp /lib/systemd/system/sniproxy.service /lib/systemd/system/sniproxy.service.bak

        # 创建修正的服务文件
        cat > /lib/systemd/system/sniproxy.service <<'EOF'
[Unit]
Description=HTTPS SNI Proxy
After=network.target
Documentation=man:sniproxy(8) file:///usr/share/doc/sniproxy/

[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
ExecStart=/usr/sbin/sniproxy
ExecStop=/bin/kill -TERM $MAINPID
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    # 重载systemd配置
    systemctl daemon-reload

    # 启用并启动服务
    systemctl enable sniproxy
    systemctl restart sniproxy

    # 等待服务启动
    sleep 2

    if systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] sniproxy 安装并启动成功"
        # 检查进程状态
        ps aux | grep '[s]niproxy' | head -2
    else
        echo -e "[${yellow}Warning${plain}] sniproxy 启动可能有问题"
        echo -e "[${yellow}提示${plain}] 检查端口: lsof -i :80 && lsof -i :443"

        # 显示错误信息
        journalctl -u sniproxy -n 10 --no-pager
    fi
}

configure_firewall() {
    echo -e "[${green}Info${plain}] 配置防火墙规则..."

    if command -v ufw > /dev/null; then
        ufw allow 53/tcp > /dev/null 2>&1
        ufw allow 53/udp > /dev/null 2>&1
        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow 443/tcp > /dev/null 2>&1
        echo -e "[${green}Success${plain}] UFW防火墙规则已配置"
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-service=dns > /dev/null 2>&1
        firewall-cmd --permanent --add-service=http > /dev/null 2>&1
        firewall-cmd --permanent --add-service=https > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        echo -e "[${green}Success${plain}] Firewalld规则已配置"
    else
        iptables -I INPUT -p tcp --dport 53 -j ACCEPT
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        echo -e "[${green}Success${plain}] iptables规则已配置"
    fi
}

show_status() {
    external_ip=$(get_external_ip)

    echo -e "\n${blue}======== 服务状态 ========${plain}"

    if systemctl is-active --quiet dnsmasq; then
        echo -e "DNSMasq: [${green}运行中${plain}]"
    else
        echo -e "DNSMasq: [${red}已停止${plain}]"
    fi

    if systemctl is-active --quiet sniproxy; then
        echo -e "SNIProxy: [${green}运行中${plain}]"
    else
        echo -e "SNIProxy: [${red}已停止${plain}]"
    fi

    echo -e "\n${blue}======== 配置信息 ========${plain}"
    echo -e "服务器IP: ${green}${external_ip}${plain}"
    echo -e "DNS端口: ${green}53${plain}"
    echo -e "HTTP端口: ${green}80${plain}"
    echo -e "HTTPS端口: ${green}443${plain}"

    echo -e "\n${blue}======== 客户端配置 ========${plain}"
    echo -e "将设备的DNS服务器设置为: ${green}${external_ip}${plain}"

    echo -e "\n${blue}======== 测试命令 ========${plain}"
    echo -e "nslookup netflix.com ${external_ip}"
    echo -e "dig @${external_ip} youtube.com"
}

restart_services() {
    echo -e "[${green}Info${plain}] 重启服务..."

    # 先杀死残留进程
    pkill -9 sniproxy 2>/dev/null
    sleep 1

    systemctl restart dnsmasq
    systemctl restart sniproxy

    if systemctl is-active --quiet dnsmasq && systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] 服务重启成功"
    else
        echo -e "[${yellow}Warning${plain}] 部分服务可能未成功启动"
        show_status
    fi
}

uninstall_all() {
    echo -e "[${yellow}Warning${plain}] 确定要卸载所有组件吗? [y/N]"
    read -r response

    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "[${green}Info${plain}] 取消卸载"
        return
    fi

    echo -e "[${green}Info${plain}] 彻底停止所有服务..."

    # 停止并禁用服务
    systemctl stop dnsmasq 2>/dev/null
    systemctl stop sniproxy 2>/dev/null
    systemctl disable dnsmasq 2>/dev/null
    systemctl disable sniproxy 2>/dev/null

    # 强制杀死所有相关进程
    pkill -9 dnsmasq 2>/dev/null
    pkill -9 sniproxy 2>/dev/null
    killall -9 sniproxy 2>/dev/null
    killall -9 dnsmasq 2>/dev/null

    echo -e "[${green}Info${plain}] 卸载软件包..."
    if [ "$PKG_MANAGER" == "apt-get" ]; then
        apt-get remove --purge -y dnsmasq sniproxy dnsmasq-base
        # 清理依赖包
        apt-get autoremove -y
    else
        yum remove -y dnsmasq sniproxy
        yum autoremove -y
    fi

    echo -e "[${green}Info${plain}] 彻底清理所有配置和日志文件..."

    # 清理配置文件
    rm -f /etc/dnsmasq.conf
    rm -f /etc/sniproxy.conf
    rm -rf /etc/dnsmasq.d

    # 清理日志文件
    rm -rf /var/log/dnsmasq*
    rm -rf /var/log/sniproxy*
    rm -rf /var/log/dns-proxy

    # 清理运行时文件
    rm -f /var/run/dnsmasq.pid
    rm -f /var/run/sniproxy.pid

    # 清理systemd残留
    rm -f /etc/systemd/system/sniproxy.service
    rm -f /etc/systemd/system/dnsmasq.service
    rm -f /lib/systemd/system/sniproxy.service
    rm -f /lib/systemd/system/dnsmasq.service
    systemctl daemon-reload

    # 恢复DNS解析
    echo -e "[${green}Info${plain}] 恢复系统DNS设置..."
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF

    # 恢复systemd-resolved（如果系统支持）
    if systemctl list-unit-files | grep -q systemd-resolved; then
        systemctl enable systemd-resolved 2>/dev/null
        systemctl start systemd-resolved 2>/dev/null
    fi

    echo -e "[${green}Success${plain}] 卸载完成！所有组件已彻底清理"
}

show_menu() {
    echo -e "\n${blue}======== DNS流媒体解锁服务 ========${plain}"
    echo "1. 完整安装（DNSMasq + SNIProxy）"
    echo "2. 仅安装 DNSMasq"
    echo "3. 仅安装 SNIProxy"
    echo "4. 查看服务状态"
    echo "5. 重启服务"
    echo "6. 修复SNIProxy"
    echo "7. 卸载所有组件"
    echo "0. 退出"
    echo -e "${blue}====================================${plain}"
}

fix_sniproxy() {
    echo -e "[${green}Info${plain}] 修复SNIProxy..."

    # 彻底停止服务
    systemctl stop sniproxy 2>/dev/null
    systemctl kill sniproxy 2>/dev/null

    # 强制杀死所有sniproxy进程
    echo -e "[${green}Info${plain}] 清理所有sniproxy进程..."
    killall -9 sniproxy 2>/dev/null
    pkill -9 sniproxy 2>/dev/null

    # 清理可能的PID文件
    rm -f /var/run/sniproxy.pid

    # 等待进程完全结束
    sleep 3

    # 详细检查端口占用
    echo -e "[${green}Info${plain}] 检查端口占用情况..."

    port_80_used=false
    port_443_used=false

    # 检查80端口
    if lsof -i :80 > /dev/null 2>&1; then
        echo -e "[${yellow}Warning${plain}] 80端口被以下进程占用:"
        lsof -i :80 | grep LISTEN
        port_80_used=true
    else
        echo -e "[${green}✓${plain}] 80端口可用"
    fi

    # 检查443端口
    if lsof -i :443 > /dev/null 2>&1; then
        echo -e "[${yellow}Warning${plain}] 443端口被以下进程占用:"
        lsof -i :443 | grep LISTEN
        port_443_used=true
    else
        echo -e "[${green}✓${plain}] 443端口可用"
    fi

    # 如果端口被占用，询问是否强制停止
    if [ "$port_80_used" = true ] || [ "$port_443_used" = true ]; then
        echo -e "\n[${yellow}Warning${plain}] 检测到端口被占用"
        echo -e "是否强制停止占用端口的服务? [y/N]"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            # 停止常见的web服务
            for service in nginx apache2 httpd caddy; do
                if systemctl is-active --quiet $service; then
                    echo -e "[${green}Info${plain}] 停止 $service..."
                    systemctl stop $service
                    systemctl disable $service 2>/dev/null
                fi
            done

            # 再次等待
            sleep 2
        fi
    fi

    # 创建配置文件
    echo -e "[${green}Info${plain}] 创建SNIProxy配置..."
    cat > $SNIPROXY_CONFIG <<'EOF'
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listener 0.0.0.0:80 {
    proto http
    table http_hosts

    fallback 127.0.0.1:8080
}

listener 0.0.0.0:443 {
    proto tls
    table https_hosts

    fallback 127.0.0.1:8443
}

table http_hosts {
    .* *
}

table https_hosts {
    .* *
}
EOF

    # 测试配置文件
    echo -e "[${green}Info${plain}] 测试配置文件..."
    if /usr/sbin/sniproxy -c /etc/sniproxy.conf -f -n 1 2>&1 | grep -q "error"; then
        echo -e "[${red}Error${plain}] 配置文件有错误"

        # 使用最简化配置
        echo -e "[${green}Info${plain}] 使用最简化配置..."
        cat > $SNIPROXY_CONFIG <<'EOF'
user daemon

listener 0.0.0.0:80 {
    proto http
}

listener 0.0.0.0:443 {
    proto tls
}

table {
    .* *
}
EOF
    fi

    # 启动服务
    echo -e "[${green}Info${plain}] 启动SNIProxy服务..."
    systemctl daemon-reload
    systemctl start sniproxy

    # 等待服务启动
    sleep 2

    # 检查服务状态
    if systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] SNIProxy修复成功!"

        # 显示监听端口
        echo -e "\n[${green}Info${plain}] SNIProxy监听端口:"
        ss -tuln | grep -E ':80|:443' | grep LISTEN
    else
        echo -e "[${red}Error${plain}] SNIProxy启动失败"

        # 显示详细错误
        echo -e "\n[${yellow}Debug${plain}] 服务状态:"
        systemctl status sniproxy --no-pager

        echo -e "\n[${yellow}Debug${plain}] 系统日志:"
        journalctl -u sniproxy -n 20 --no-pager

        echo -e "\n[${yellow}提示${plain}] 可能的解决方案:"
        echo -e "1. 检查80/443端口是否被占用: lsof -i :80 && lsof -i :443"
        echo -e "2. 停止占用的服务: systemctl stop nginx apache2"
        echo -e "3. 检查配置文件: cat /etc/sniproxy.conf"
        echo -e "4. 手动测试: /usr/sbin/sniproxy -c /etc/sniproxy.conf -f"
    fi
}

main() {
    check_system

    if [ $# -eq 0 ]; then
        while true; do
            show_menu
            read -p "请选择 [0-7]: " choice

            case $choice in
                0)
                    echo -e "[${green}Info${plain}] 退出脚本"
                    exit 0
                    ;;
                1)
                    check_ports
                    install_dependencies
                    install_dnsmasq
                    install_sniproxy
                    configure_firewall
                    show_status
                    ;;
                2)
                    check_ports
                    install_dependencies
                    install_dnsmasq
                    configure_firewall
                    show_status
                    ;;
                3)
                    check_ports
                    install_dependencies
                    install_sniproxy
                    configure_firewall
                    show_status
                    ;;
                4)
                    show_status
                    ;;
                5)
                    restart_services
                    ;;
                6)
                    fix_sniproxy
                    ;;
                7)
                    uninstall_all
                    ;;
                *)
                    echo -e "[${red}Error${plain}] 无效的选择"
                    ;;
            esac
        done
    else
        case $1 in
            -h|--help)
                echo "使用方法: bash $0 [选项]"
                echo ""
                echo "选项:"
                echo "  -h, --help        显示帮助信息"
                echo "  -i, --install     完整安装"
                echo "  -u, --uninstall   卸载所有组件"
                echo "  -s, --status      查看服务状态"
                echo "  -r, --restart     重启服务"
                echo "  -f, --fix         修复SNIProxy"
                ;;
            -i|--install)
                check_ports
                install_dependencies
                install_dnsmasq
                install_sniproxy
                configure_firewall
                show_status
                ;;
            -u|--uninstall)
                uninstall_all
                ;;
            -s|--status)
                show_status
                ;;
            -r|--restart)
                restart_services
                ;;
            -f|--fix)
                fix_sniproxy
                ;;
            *)
                echo -e "[${red}Error${plain}] 无效的参数: $1"
                echo "使用 $0 --help 查看帮助"
                exit 1
                ;;
        esac
    fi
}

main "$@"