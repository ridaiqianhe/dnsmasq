#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root用户来执行脚本!" && exit 1

check_ports() {
    for port in 80 443 53; do
        if lsof -i :$port > /dev/null; then
            echo -e "[${red}Error${plain}] 端口 $port 被占用，无法继续安装。"
            exit 1
        fi
    done
}

get_external_ip() {
    external_ip=$(curl -s -4 ip.sb)
    echo "${external_ip}"
}

install_dnsmasq() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 dnsmasq..."
    apt-get update && apt-get install -y dnsmasq

    echo -e "[${green}Info${plain}] 配置 dnsmasq..."
    cat <<EOF > /etc/dnsmasq.conf
listen-address=$external_ip
bind-interfaces

# 代理所有域名，将所有请求解析到服务器的实际IP地址
address=/#/$external_ip

# 指定上游DNS服务器，处理非代理域名
server=8.8.8.8
server=8.8.4.4
EOF

    systemctl enable dnsmasq
    systemctl restart dnsmasq

    echo -e "[${green}Info${plain}] dnsmasq 安装并配置完成。"
}

install_sniproxy() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 sniproxy..."
    apt-get install -y sniproxy

    echo -e "[${green}Info${plain}] 配置 sniproxy..."
    cat <<EOF > /etc/sniproxy.conf
user daemon
pidfile /var/tmp/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

resolver {
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    mode ipv4_only
}

listener $external_ip:80 {
    proto http
    access_log {
        filename /var/log/sniproxy/http_access.log
        priority notice
    }
}

listener $external_ip:443 {
    proto tls
    access_log {
        filename /var/log/sniproxy/https_access.log
        priority notice
    }
}

table {
    .* *
}
EOF

    # 创建日志目录
    mkdir -p /var/log/sniproxy

    systemctl enable sniproxy
    systemctl restart sniproxy

    echo -e "[${green}Info${plain}] sniproxy 安装并配置完成。"
}

uninstall_all() {
    echo -e "[${green}Info${plain}] 卸载 dnsmasq 和 sniproxy..."
    systemctl stop dnsmasq sniproxy
    apt-get remove --purge -y dnsmasq sniproxy
    rm -f /etc/dnsmasq.conf /etc/sniproxy.conf
    rm -rf /var/log/sniproxy
    echo -e "[${green}Info${plain}] 卸载完成。"
}

show_help() {
    echo "使用方法：bash $0 [-h] [-i] [-u]"
    echo ""
    echo "  -h , --help                显示帮助信息"
    echo "  -i , --install             安装 dnsmasq 和 sniproxy 并配置所有域名代理"
    echo "  -u , --uninstall           卸载 dnsmasq 和 sniproxy"
    echo ""
}

if [[ $# = 1 ]]; then
    case $1 in
        -i|--install)
            check_ports
            install_dnsmasq
            install_sniproxy
            ;;
        -u|--uninstall)
            uninstall_all
            ;;
        -h|--help|*)
            show_help
            ;;
    esac
else
    show_help
fi
