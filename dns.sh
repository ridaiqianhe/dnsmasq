#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root用户来执行脚本!" && exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_DOMAINS_FILE="${SCRIPT_DIR}/proxy-domains.txt"
PROXY_DOMAINS_URL="https://raw.githubusercontent.com/miyouzi/dnsmasq_sniproxy_install/main/proxy-domains.txt"
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
        elif command -v netstat > /dev/null; then
            if netstat -tuln | grep -q ":$port "; then
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
        else
            echo -e "[${red}Error${plain}] 端口被占用，无法继续安装。"
            exit 1
        fi
    fi
}

stop_conflicting_services() {
    local services=("systemd-resolved" "bind9" "named" "apache2" "nginx" "httpd")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo -e "[${green}Info${plain}] 停止服务: $service"
            systemctl stop $service
            systemctl disable $service 2>/dev/null
        fi
    done
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

    echo -e "[${red}Error${plain}] 无法获取外部IP地址"
    exit 1
}

download_proxy_domains() {
    echo -e "[${green}Info${plain}] 下载流媒体域名列表..."

    if ! curl -s -L -o "${PROXY_DOMAINS_FILE}.tmp" "${PROXY_DOMAINS_URL}"; then
        echo -e "[${yellow}Warning${plain}] 无法下载域名列表，使用本地文件"
        if [ ! -f "${PROXY_DOMAINS_FILE}" ]; then
            echo -e "[${red}Error${plain}] 本地域名列表文件不存在: ${PROXY_DOMAINS_FILE}"
            return 1
        fi
    else
        mv "${PROXY_DOMAINS_FILE}.tmp" "${PROXY_DOMAINS_FILE}"
        echo -e "[${green}Info${plain}] 域名列表更新成功"
    fi

    return 0
}

install_dependencies() {
    echo -e "[${green}Info${plain}] 安装依赖包..."

    $PKG_UPDATE

    local packages=("curl" "wget" "lsof" "iptables" "ipset")

    for pkg in "${packages[@]}"; do
        if ! command -v $pkg > /dev/null; then
            echo -e "[${green}Info${plain}] 安装 $pkg..."
            $PKG_MANAGER install -y $pkg
        fi
    done
}

install_dnsmasq() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 dnsmasq..."
    echo -e "[${green}Info${plain}] 服务器IP: ${external_ip}"

    $PKG_MANAGER install -y dnsmasq

    echo -e "[${green}Info${plain}] 配置 dnsmasq..."

    download_proxy_domains

    cat <<EOF > $DNSMASQ_CONFIG
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

# 国内DNS服务器（用于国内域名）
server=/cn/223.5.5.5
server=/cn/119.29.29.29

# 日志配置
log-queries
log-facility=/var/log/dns-proxy/dnsmasq.log

# 流媒体域名解析配置
EOF

    if [ -f "${PROXY_DOMAINS_FILE}" ]; then
        echo -e "[${green}Info${plain}] 添加流媒体域名解析规则..."
        while IFS= read -r domain || [ -n "$domain" ]; do
            [ -z "$domain" ] && continue
            [[ $domain == \#* ]] && continue
            echo "address=/${domain}/${external_ip}" >> $DNSMASQ_CONFIG
        done < "${PROXY_DOMAINS_FILE}"
    fi

    mkdir -p $LOG_DIR
    touch $LOG_DIR/dnsmasq.log
    chown nobody:nogroup $LOG_DIR/dnsmasq.log

    systemctl enable dnsmasq
    systemctl restart dnsmasq

    if systemctl is-active --quiet dnsmasq; then
        echo -e "[${green}Success${plain}] dnsmasq 安装并启动成功"
    else
        echo -e "[${red}Error${plain}] dnsmasq 启动失败"
        systemctl status dnsmasq
        exit 1
    fi
}

install_sniproxy() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 sniproxy..."

    $PKG_MANAGER install -y sniproxy

    echo -e "[${green}Info${plain}] 配置 sniproxy..."

    # 创建正确的sniproxy配置文件
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
}

listener 0.0.0.0:443 {
    proto tls
    table https_hosts
}

table http_hosts {
    .* *
}

table https_hosts {
    .* *
}
EOF

    mkdir -p $LOG_DIR

    systemctl enable sniproxy
    systemctl restart sniproxy

    if systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] sniproxy 安装并启动成功"
    else
        echo -e "[${yellow}Warning${plain}] sniproxy 启动失败（可能443端口被占用）"
        echo -e "[${yellow}Info${plain}] 如需HTTPS代理，请手动停止占用443端口的服务"
    fi
}

configure_firewall() {
    echo -e "[${green}Info${plain}] 配置防火墙规则..."

    # 检查防火墙类型
    if command -v ufw > /dev/null; then
        echo -e "[${green}Info${plain}] 配置 UFW 防火墙..."
        ufw allow 53/tcp
        ufw allow 53/udp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw --force enable
    elif command -v firewall-cmd > /dev/null; then
        echo -e "[${green}Info${plain}] 配置 firewalld..."
        firewall-cmd --permanent --add-service=dns
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    else
        echo -e "[${green}Info${plain}] 配置 iptables..."
        iptables -I INPUT -p tcp --dport 53 -j ACCEPT
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT

        # 保存规则
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            $PKG_MANAGER install -y iptables-persistent
            netfilter-persistent save
        elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            service iptables save
        fi
    fi

    echo -e "[${green}Success${plain}] 防火墙规则配置完成"
}

show_status() {
    external_ip=$(get_external_ip)

    echo -e "\n${blue}======== 服务状态 ========${plain}"

    # DNSMasq 状态
    if systemctl is-active --quiet dnsmasq; then
        echo -e "DNSMasq: [${green}运行中${plain}]"
    else
        echo -e "DNSMasq: [${red}已停止${plain}]"
    fi

    # SNIProxy 状态
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

    if [ -f "${PROXY_DOMAINS_FILE}" ]; then
        domain_count=$(grep -v '^#' "${PROXY_DOMAINS_FILE}" | grep -v '^$' | wc -l)
        echo -e "已配置流媒体域名数: ${green}${domain_count}${plain}"
    fi

    echo -e "\n${blue}======== 日志文件 ========${plain}"
    echo -e "DNSMasq日志: ${LOG_DIR}/dnsmasq.log"
    echo -e "SNIProxy访问日志: ${LOG_DIR}/sniproxy_access.log"
    echo -e "HTTP日志: ${LOG_DIR}/http_access.log"
    echo -e "HTTPS日志: ${LOG_DIR}/https_access.log"
}

restart_services() {
    echo -e "[${green}Info${plain}] 重启服务..."

    systemctl restart dnsmasq
    systemctl restart sniproxy

    sleep 2

    if systemctl is-active --quiet dnsmasq && systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] 服务重启成功"
    else
        echo -e "[${red}Error${plain}] 服务重启失败"
        show_status
        exit 1
    fi
}

uninstall_all() {
    echo -e "[${yellow}Warning${plain}] 确定要卸载所有组件吗? [y/N]"
    read -r response

    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "[${green}Info${plain}] 取消卸载"
        return
    fi

    echo -e "[${green}Info${plain}] 停止服务..."
    systemctl stop dnsmasq sniproxy 2>/dev/null
    systemctl disable dnsmasq sniproxy 2>/dev/null

    echo -e "[${green}Info${plain}] 卸载软件包..."
    if [ "$PKG_MANAGER" == "apt-get" ]; then
        apt-get remove --purge -y dnsmasq sniproxy
    else
        yum remove -y dnsmasq sniproxy
    fi

    echo -e "[${green}Info${plain}] 清理配置文件..."
    rm -f $DNSMASQ_CONFIG $SNIPROXY_CONFIG
    rm -rf $LOG_DIR
    rm -f /etc/systemd/system/sniproxy.service

    echo -e "[${green}Success${plain}] 卸载完成"
}


show_menu() {
    echo -e "\n${blue}======== DNS流媒体解锁服务 ========${plain}"
    echo "1. 完整安装（DNSMasq + SNIProxy）"
    echo "2. 仅安装 DNSMasq"
    echo "3. 仅安装 SNIProxy"
    echo "4. 查看服务状态"
    echo "5. 重启服务"
    echo "6. 卸载所有组件"
    echo "0. 退出"
    echo -e "${blue}====================================${plain}"
}

main() {
    check_system

    if [ $# -eq 0 ]; then
        while true; do
            show_menu
            read -p "请选择 [0-6]: " choice

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
                echo "  -d, --update      更新域名列表"
                echo ""
                ;;
            -i|--install)
                check_ports
                install_dependencies
                install_dnsmasq
                install_sniproxy
                configure_firewall
                setup_cron
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
            -d|--update)
                update_domains
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