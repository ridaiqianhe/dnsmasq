#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# 高亮颜色
BRed='\033[1;31m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BBlue='\033[1;34m'
BMagenta='\033[1;35m'
BCyan='\033[1;36m'
BWhite='\033[1;37m'

# 背景色
On_Red='\033[41m'
On_Green='\033[42m'
On_Yellow='\033[43m'
On_Blue='\033[44m'
On_Cyan='\033[46m'

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${BRed}[错误]${NC} 请使用root权限运行！" && exit 1

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DNSMASQ_CONFIG="/etc/dnsmasq.conf"
DNSMASQ_CUSTOM="/etc/dnsmasq.d/custom.conf"
SNIPROXY_CONFIG="/etc/sniproxy.conf"
LOG_DIR="/var/log/dns-proxy"
CUSTOM_DOMAINS_FILE="/etc/dnsmasq.d/custom-domains.conf"
PROXY_DOMAINS_FILE="${SCRIPT_DIR}/proxy-domains.txt"
PROXY_DOMAINS_URL="https://raw.githubusercontent.com/miyouzi/dnsmasq_sniproxy_install/main/proxy-domains.txt"

# DNS域名配置
declare -A dns_domains

# 台湾媒体
dns_domains["TW"]="kfs.io kktv-theater.kk.stream kkbox.com kkbox.com.tw kktv.com.tw kktv.me litv.tv myvideo.net.tw 4gtv.tv ofiii.com linetv.tw hamivideo.hinet.net catchplay.com bahamut.com.tw gamer.com.tw video.friday.tw"

# 日本媒体
dns_domains["JP"]="nhk.jp nhk.or.jp dmm.co.jp dmm.com videomarket.jp abema.io abema.tv ameba.jp nicovideo.jp paravi.jp unext.jp hulu.jp tver.jp gyao.yahoo.co.jp wowow.co.jp animestore.docomo.ne.jp fujitv.co.jp radiko.jp rakuten.co.jp mora.jp music.jp"

# 香港媒体
dns_domains["HK"]="nowe.com nowestatic.com now.com viu.com viu.now.com viu.tv mytvsuper.com tvb.com tvb.com.au tvbc.com.cn tvbeventpower.com.hk tvbusa.com tvbweekly.com hoy.tv tvbanywhere.com tvbanywhere.com.sg"

# Disney
dns_domains["Disney"]="disney.connections.edge.bamgrid.com disney.api.edge.bamgrid.com disney-plus.net disneyplus.com dssott.com disneynow.com disneystreaming.com cdn.registerdisney.go.com"

# Netflix
dns_domains["Netflix"]="netflix.com netflix.net nflximg.com nflximg.net nflxvideo.net nflxext.com nflxso.net"

# Amazon Prime Video
dns_domains["Prime"]="aiv-cdn.net aiv-delivery.net amazonvideo.com atv-ext-eu.amazon.com atv-ext-fe.amazon.com atv-ext.amazon.com atv-ps.amazon.com primevideo.com pv-cdn.net video.a2z.com"

# DAZN
dns_domains["DAZN"]="dazn-api.com dazn.com dazndn.com indazn.com dcalivedazn.akamaized.net dcblivedazn.akamaized.net"

# HBO/Max
dns_domains["HBO"]="max.com hbo.com hbogo.com hbomax.com hbomaxcdn.com hbonow.com maxgo.com discomax.com"

# AI平台
dns_domains["AI"]="openai.com chatgpt.com sora.com oaistatic.com oaiusercontent.com anthropic.com claude.ai gemini.google.com aistudio.google.com copilot.microsoft.com"

# Youtube
dns_domains["Youtube"]="youtube.com youtubei.googleapis.com googlevideo.com ytimg.com ggpht.com"

# Google
dns_domains["Google"]="google.com googleapis.com googleusercontent.com gstatic.com"

# Instagram
dns_domains["Instagram"]="instagram.com cdninstagram.com"

# TikTok
dns_domains["TikTok"]="byteoversea.com ibytedtos.com ipstatp.com muscdn.com musical.ly tiktok.com tik-tokapi.com tiktokcdn.com tiktokv.com"

# iQiyi
dns_domains["iQiyi"]="71.am iq.com iqiyi.com iqiyipic.com pps.tv ppsimg.com qiyi.com qiyipic.com qy.net"

# BiliBili
dns_domains["BiliBili"]="bilibili.com bilibili.tv bilivideo.com biliapi.net biliapi.com"

# Steam
dns_domains["Steam"]="steampowered.com steamcommunity.com steamgames.com steamusercontent.com steamcontent.com steamstatic.com akamaihd.net"

# 韩国媒体
dns_domains["Korea"]="wavve.com pooq.co.kr tving.com coupangplay.com naver.com navercorp.com pstatic.net smartmediarep.com afreecatv.com kbs.co.kr jtbc.co.kr kocowa.com"

# 速度测试
dns_domains["Speedtest"]="fast.com ooklaserver.net speed.cloudflare.com speed.dler.io ip.sb ip.skk.moe speedtest.net"

# 检查系统类型
check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${BRed}[错误]${NC} 无法检测操作系统版本！"
        exit 1
    fi

    case $OS in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update"
            ;;
        *)
            echo -e "${BRed}[错误]${NC} 不支持的操作系统: $OS"
            exit 1
            ;;
    esac
}

# 获取外部IP
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

    echo -e "${BRed}[错误]${NC} 无法获取外部IP地址"
    return 1
}

# 检查端口
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
        echo -e "${BYellow}[警告]${NC} 以下端口被占用: ${occupied[@]}"
        echo -e "是否尝试停止占用的服务? [y/N]"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            stop_conflicting_services
        else
            echo -e "${BRed}[错误]${NC} 端口被占用，无法继续安装。"
            return 1
        fi
    fi

    return 0
}

# 停止冲突服务
stop_conflicting_services() {
    local services=("systemd-resolved" "bind9" "named" "apache2" "nginx" "httpd")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo -e "${BGreen}[信息]${NC} 停止服务: $service"
            systemctl stop $service
            systemctl disable $service 2>/dev/null
        fi
    done
}

# 安装依赖
install_dependencies() {
    echo -e "${BGreen}[信息]${NC} 安装依赖包..."

    $PKG_UPDATE > /dev/null 2>&1

    local packages=("curl" "wget" "lsof" "iptables" "ipset" "git")

    for pkg in "${packages[@]}"; do
        if ! command -v $pkg > /dev/null; then
            echo -e "${BGreen}[信息]${NC} 安装 $pkg..."
            $PKG_MANAGER install -y $pkg > /dev/null 2>&1
        fi
    done
}

# 安装dnsmasq
install_dnsmasq() {
    local external_ip=$(get_external_ip)
    if [ -z "$external_ip" ]; then
        return 1
    fi

    echo -e "${BGreen}[信息]${NC} 安装 dnsmasq..."
    echo -e "${BGreen}[信息]${NC} 服务器IP: ${BWhite}${external_ip}${NC}"

    # 停止systemd-resolved
    if systemctl is-active --quiet systemd-resolved; then
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved 2>/dev/null
    fi

    # 安装dnsmasq
    $PKG_MANAGER install -y dnsmasq > /dev/null 2>&1

    # 创建配置目录
    mkdir -p /etc/dnsmasq.d
    mkdir -p $LOG_DIR

    # 基础配置
    cat > $DNSMASQ_CONFIG <<EOF
# 基础配置
user=nobody
no-resolv
no-poll
expand-hosts
listen-address=127.0.0.1,${external_ip}
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
log-queries
log-facility=${LOG_DIR}/dnsmasq.log

# 包含自定义配置
conf-dir=/etc/dnsmasq.d/,*.conf
EOF

    # 创建日志文件
    touch $LOG_DIR/dnsmasq.log
    chown nobody:nogroup $LOG_DIR/dnsmasq.log

    # 配置resolv.conf
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    chattr +i /etc/resolv.conf

    # 启动服务
    systemctl unmask dnsmasq 2>/dev/null
    systemctl enable dnsmasq
    systemctl restart dnsmasq

    if systemctl is-active --quiet dnsmasq; then
        echo -e "${BGreen}[成功]${NC} dnsmasq 安装并启动成功"
        return 0
    else
        echo -e "${BRed}[错误]${NC} dnsmasq 启动失败"
        systemctl status dnsmasq
        return 1
    fi
}

# 安装sniproxy
install_sniproxy() {
    local external_ip=$(get_external_ip)
    if [ -z "$external_ip" ]; then
        return 1
    fi

    echo -e "${BGreen}[信息]${NC} 安装 sniproxy..."

    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        $PKG_MANAGER install -y sniproxy > /dev/null 2>&1
    else
        echo -e "${BGreen}[信息]${NC} 从源码编译安装 sniproxy..."
        $PKG_MANAGER install -y gcc make autoconf automake libtool gettext libev-devel pcre-devel udns-devel > /dev/null 2>&1

        cd /tmp
        git clone https://github.com/dlundquist/sniproxy.git
        cd sniproxy
        ./autogen.sh
        ./configure
        make && make install

        cat > /etc/systemd/system/sniproxy.service <<EOF
[Unit]
Description=SNI Proxy
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/sbin/sniproxy -c /etc/sniproxy.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    # 配置sniproxy
    cat > $SNIPROXY_CONFIG <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

access_log {
    filename $LOG_DIR/sniproxy_access.log
    priority notice
}

resolver {
    nameserver 127.0.0.1
    mode ipv4_only
}

listener $external_ip:80 {
    proto http

    table {
        .* *
    }

    access_log {
        filename $LOG_DIR/http_access.log
        priority notice
    }
}

listener $external_ip:443 {
    proto tls

    table {
        .* *
    }

    access_log {
        filename $LOG_DIR/https_access.log
        priority notice
    }
}
EOF

    # 创建日志文件
    touch $LOG_DIR/sniproxy_access.log
    touch $LOG_DIR/http_access.log
    touch $LOG_DIR/https_access.log

    # 启动服务
    systemctl enable sniproxy
    systemctl restart sniproxy

    if systemctl is-active --quiet sniproxy; then
        echo -e "${BGreen}[成功]${NC} sniproxy 安装并启动成功"
        return 0
    else
        echo -e "${BRed}[错误]${NC} sniproxy 启动失败"
        systemctl status sniproxy
        return 1
    fi
}

# 配置防火墙
configure_firewall() {
    echo -e "${BGreen}[信息]${NC} 配置防火墙规则..."

    if command -v ufw > /dev/null; then
        echo -e "${BGreen}[信息]${NC} 配置 UFW 防火墙..."
        ufw allow 53/tcp > /dev/null 2>&1
        ufw allow 53/udp > /dev/null 2>&1
        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow 443/tcp > /dev/null 2>&1
        ufw --force enable > /dev/null 2>&1
    elif command -v firewall-cmd > /dev/null; then
        echo -e "${BGreen}[信息]${NC} 配置 firewalld..."
        firewall-cmd --permanent --add-service=dns > /dev/null 2>&1
        firewall-cmd --permanent --add-service=http > /dev/null 2>&1
        firewall-cmd --permanent --add-service=https > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
    else
        echo -e "${BGreen}[信息]${NC} 配置 iptables..."
        iptables -I INPUT -p tcp --dport 53 -j ACCEPT
        iptables -I INPUT -p udp --dport 53 -j ACCEPT
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT

        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            $PKG_MANAGER install -y iptables-persistent > /dev/null 2>&1
            netfilter-persistent save > /dev/null 2>&1
        elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            service iptables save > /dev/null 2>&1
        fi
    fi

    echo -e "${BGreen}[成功]${NC} 防火墙规则配置完成"
}

# 配置流媒体DNS
configure_streaming_dns() {
    clear
    echo -e "${On_Blue}                                                      ${NC}"
    echo -e "${BWhite}              配置流媒体DNS解锁                      ${NC}"
    echo -e "${On_Blue}                                                      ${NC}\n"

    echo -e "${BWhite}请选择DNS区域:${NC}\n"

    echo -e "${BCyan}亚洲地区:${NC}"
    echo -e "  ${BYellow}1.${NC}  台湾媒体 (KKTV/LiTV/MyVideo/Bahamut等)"
    echo -e "  ${BYellow}2.${NC}  日本媒体 (NHK/DMM/Abema/Hulu JP等)"
    echo -e "  ${BYellow}3.${NC}  香港媒体 (Now/ViuTV/MyTVSuper/TVB等)"
    echo -e "  ${BYellow}4.${NC}  韩国媒体 (Wavve/Tving/Coupang等)"

    echo -e "\n${BCyan}全球流媒体:${NC}"
    echo -e "  ${BYellow}5.${NC}  Disney+"
    echo -e "  ${BYellow}6.${NC}  Netflix"
    echo -e "  ${BYellow}7.${NC}  Amazon Prime Video"
    echo -e "  ${BYellow}8.${NC}  DAZN"
    echo -e "  ${BYellow}9.${NC}  HBO/Max"
    echo -e "  ${BYellow}10.${NC} Youtube"

    echo -e "\n${BCyan}社交媒体:${NC}"
    echo -e "  ${BYellow}11.${NC} Google"
    echo -e "  ${BYellow}12.${NC} Instagram"
    echo -e "  ${BYellow}13.${NC} TikTok"

    echo -e "\n${BCyan}中文平台:${NC}"
    echo -e "  ${BYellow}14.${NC} iQiyi爱奇艺"
    echo -e "  ${BYellow}15.${NC} BiliBili哔哩哔哩"

    echo -e "\n${BCyan}其他服务:${NC}"
    echo -e "  ${BYellow}16.${NC} Steam游戏平台"
    echo -e "  ${BYellow}17.${NC} AI平台 (OpenAI/Claude/Gemini等)"
    echo -e "  ${BYellow}18.${NC} 速度测试 (Fast/Speedtest等)"

    echo -e "\n${BYellow}0.${NC}  返回主菜单\n"

    read -p "请选择 [0-18]: " choice

    if [ "$choice" == "0" ]; then
        return
    fi

    # 映射选择到区域名称
    local region_name=""
    case $choice in
        1) region_name="TW";;
        2) region_name="JP";;
        3) region_name="HK";;
        4) region_name="Korea";;
        5) region_name="Disney";;
        6) region_name="Netflix";;
        7) region_name="Prime";;
        8) region_name="DAZN";;
        9) region_name="HBO";;
        10) region_name="Youtube";;
        11) region_name="Google";;
        12) region_name="Instagram";;
        13) region_name="TikTok";;
        14) region_name="iQiyi";;
        15) region_name="BiliBili";;
        16) region_name="Steam";;
        17) region_name="AI";;
        18) region_name="Speedtest";;
        *) echo -e "${BRed}[错误]${NC} 无效的选择"; return;;
    esac

    echo -e "\n${BWhite}请输入DNS服务器IP地址:${NC}"
    echo -e "${BYellow}提示:${NC} 输入要解锁的DNS服务器IP（如: 8.8.8.8）"
    echo -e "      留空则删除该区域的所有DNS配置"
    read -p "DNS IP: " dns_ip

    # 删除旧配置
    local config_file="/etc/dnsmasq.d/${region_name}.conf"
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        echo -e "${BYellow}[信息]${NC} 已删除旧的${region_name}配置"
    fi

    if [ -n "$dns_ip" ]; then
        # 验证IP格式
        if ! [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${BRed}[错误]${NC} 无效的IP地址格式"
            return
        fi

        # 创建新配置
        echo "# ${region_name} DNS配置" > "$config_file"
        echo "# 配置时间: $(date)" >> "$config_file"
        echo "" >> "$config_file"

        for domain in ${dns_domains[$region_name]}; do
            echo "server=/${domain}/${dns_ip}" >> "$config_file"
        done

        echo -e "${BGreen}[成功]${NC} ${region_name}区域DNS已配置为: ${BWhite}${dns_ip}${NC}"

        # 重启dnsmasq
        systemctl restart dnsmasq
        if systemctl is-active --quiet dnsmasq; then
            echo -e "${BGreen}[成功]${NC} dnsmasq已重启生效"
        else
            echo -e "${BRed}[错误]${NC} dnsmasq重启失败"
        fi
    else
        echo -e "${BYellow}[信息]${NC} 已清除${region_name}的DNS配置"
        systemctl restart dnsmasq
    fi
}

# 添加自定义域名
add_custom_domain() {
    clear
    echo -e "${On_Blue}                                                      ${NC}"
    echo -e "${BWhite}              添加自定义域名解析                      ${NC}"
    echo -e "${On_Blue}                                                      ${NC}\n"

    echo -e "${BWhite}请输入要添加的域名:${NC}"
    echo -e "${BYellow}示例:${NC} example.com"
    read -p "域名: " domain

    if [ -z "$domain" ]; then
        echo -e "${BRed}[错误]${NC} 域名不能为空"
        return
    fi

    echo -e "\n${BWhite}请输入DNS服务器IP:${NC}"
    echo -e "${BYellow}示例:${NC} 8.8.8.8"
    read -p "DNS IP: " dns_ip

    if ! [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${BRed}[错误]${NC} 无效的IP地址格式"
        return
    fi

    # 添加到自定义配置文件
    echo "server=/${domain}/${dns_ip}" >> $CUSTOM_DOMAINS_FILE

    echo -e "${BGreen}[成功]${NC} 已添加自定义域名解析:"
    echo -e "  域名: ${BWhite}${domain}${NC}"
    echo -e "  DNS: ${BWhite}${dns_ip}${NC}"

    # 重启dnsmasq
    systemctl restart dnsmasq
}

# 批量导入域名
import_domains() {
    clear
    echo -e "${On_Blue}                                                      ${NC}"
    echo -e "${BWhite}              批量导入域名配置                        ${NC}"
    echo -e "${On_Blue}                                                      ${NC}\n"

    echo -e "${BWhite}请输入域名列表文件路径:${NC}"
    echo -e "${BYellow}格式:${NC} 每行一个域名"
    read -p "文件路径: " file_path

    if [ ! -f "$file_path" ]; then
        echo -e "${BRed}[错误]${NC} 文件不存在: $file_path"
        return
    fi

    echo -e "\n${BWhite}请输入DNS服务器IP:${NC}"
    read -p "DNS IP: " dns_ip

    if ! [[ $dns_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${BRed}[错误]${NC} 无效的IP地址格式"
        return
    fi

    local count=0
    while IFS= read -r domain || [ -n "$domain" ]; do
        [ -z "$domain" ] && continue
        [[ $domain == \#* ]] && continue

        echo "server=/${domain}/${dns_ip}" >> $CUSTOM_DOMAINS_FILE
        ((count++))
    done < "$file_path"

    echo -e "${BGreen}[成功]${NC} 已导入 ${BWhite}${count}${NC} 个域名"

    # 重启dnsmasq
    systemctl restart dnsmasq
}

# 查看当前配置
show_dns_config() {
    clear
    echo -e "${On_Cyan}                                                      ${NC}"
    echo -e "${BWhite}              当前DNS配置状态                         ${NC}"
    echo -e "${On_Cyan}                                                      ${NC}\n"

    local external_ip=$(get_external_ip)
    echo -e "${BCyan}服务器信息:${NC}"
    echo -e "  外部IP: ${BWhite}${external_ip}${NC}"
    echo -e "  系统DNS: ${BWhite}$(grep 'nameserver' /etc/resolv.conf | awk '{ print $2 }' | tr '\n' ' ')${NC}"

    echo -e "\n${BCyan}服务状态:${NC}"

    # DNSMasq状态
    if systemctl is-active --quiet dnsmasq; then
        echo -e "  DNSMasq: ${BGreen}[运行中]${NC}"
    else
        echo -e "  DNSMasq: ${BRed}[已停止]${NC}"
    fi

    # SNIProxy状态
    if systemctl is-active --quiet sniproxy; then
        echo -e "  SNIProxy: ${BGreen}[运行中]${NC}"
    else
        echo -e "  SNIProxy: ${BRed}[已停止]${NC}"
    fi

    echo -e "\n${BCyan}已配置的DNS解析:${NC}"

    # 检查各区域配置
    for region in TW JP HK Korea Disney Netflix Prime DAZN HBO Youtube Google Instagram TikTok iQiyi BiliBili Steam AI Speedtest; do
        local config_file="/etc/dnsmasq.d/${region}.conf"
        if [ -f "$config_file" ]; then
            local dns_ip=$(grep "server=" "$config_file" | head -1 | cut -d'/' -f3)
            printf "  %-15s: ${BWhite}%-15s${NC}\n" "$region" "$dns_ip"
        fi
    done

    # 自定义域名数量
    if [ -f "$CUSTOM_DOMAINS_FILE" ]; then
        local custom_count=$(grep -c "^server=" "$CUSTOM_DOMAINS_FILE")
        echo -e "\n  自定义域名: ${BWhite}${custom_count}${NC} 个"
    fi

    echo -e "\n${BCyan}客户端配置说明:${NC}"
    echo -e "  将设备的DNS服务器设置为: ${BWhite}${external_ip}${NC}"

    echo -e "\n${BCyan}日志文件位置:${NC}"
    echo -e "  DNSMasq日志: ${BWhite}${LOG_DIR}/dnsmasq.log${NC}"
    echo -e "  HTTP访问日志: ${BWhite}${LOG_DIR}/http_access.log${NC}"
    echo -e "  HTTPS访问日志: ${BWhite}${LOG_DIR}/https_access.log${NC}"

    echo -e "\n按任意键返回..."
    read -n 1
}

# 查看日志
view_logs() {
    clear
    echo -e "${On_Blue}                                                      ${NC}"
    echo -e "${BWhite}              查看系统日志                            ${NC}"
    echo -e "${On_Blue}                                                      ${NC}\n"

    echo -e "${BWhite}请选择要查看的日志:${NC}\n"
    echo -e "  ${BYellow}1.${NC} DNSMasq查询日志"
    echo -e "  ${BYellow}2.${NC} SNIProxy访问日志"
    echo -e "  ${BYellow}3.${NC} HTTP访问日志"
    echo -e "  ${BYellow}4.${NC} HTTPS访问日志"
    echo -e "  ${BYellow}5.${NC} 实时监控DNS查询"
    echo -e "  ${BYellow}0.${NC} 返回主菜单\n"

    read -p "请选择 [0-5]: " choice

    case $choice in
        1)
            if [ -f "$LOG_DIR/dnsmasq.log" ]; then
                echo -e "\n${BCyan}最近50条DNSMasq查询记录:${NC}\n"
                tail -n 50 $LOG_DIR/dnsmasq.log
            else
                echo -e "${BRed}[错误]${NC} 日志文件不存在"
            fi
            ;;
        2)
            if [ -f "$LOG_DIR/sniproxy_access.log" ]; then
                echo -e "\n${BCyan}最近50条SNIProxy访问记录:${NC}\n"
                tail -n 50 $LOG_DIR/sniproxy_access.log
            else
                echo -e "${BRed}[错误]${NC} 日志文件不存在"
            fi
            ;;
        3)
            if [ -f "$LOG_DIR/http_access.log" ]; then
                echo -e "\n${BCyan}最近50条HTTP访问记录:${NC}\n"
                tail -n 50 $LOG_DIR/http_access.log
            else
                echo -e "${BRed}[错误]${NC} 日志文件不存在"
            fi
            ;;
        4)
            if [ -f "$LOG_DIR/https_access.log" ]; then
                echo -e "\n${BCyan}最近50条HTTPS访问记录:${NC}\n"
                tail -n 50 $LOG_DIR/https_access.log
            else
                echo -e "${BRed}[错误]${NC} 日志文件不存在"
            fi
            ;;
        5)
            if [ -f "$LOG_DIR/dnsmasq.log" ]; then
                echo -e "\n${BCyan}实时监控DNS查询 (Ctrl+C退出):${NC}\n"
                tail -f $LOG_DIR/dnsmasq.log
            else
                echo -e "${BRed}[错误]${NC} 日志文件不存在"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${BRed}[错误]${NC} 无效的选择"
            ;;
    esac

    echo -e "\n按任意键返回..."
    read -n 1
}

# 高级设置
advanced_settings() {
    clear
    echo -e "${On_Magenta}                                                      ${NC}"
    echo -e "${BWhite}              高级设置                                ${NC}"
    echo -e "${On_Magenta}                                                      ${NC}\n"

    echo -e "${BWhite}请选择操作:${NC}\n"
    echo -e "  ${BYellow}1.${NC} 设置DNS缓存大小"
    echo -e "  ${BYellow}2.${NC} 设置最小TTL时间"
    echo -e "  ${BYellow}3.${NC} 添加额外监听地址"
    echo -e "  ${BYellow}4.${NC} 配置上游DNS服务器"
    echo -e "  ${BYellow}5.${NC} 启用/禁用查询日志"
    echo -e "  ${BYellow}6.${NC} 清空DNS缓存"
    echo -e "  ${BYellow}7.${NC} 设置定时任务"
    echo -e "  ${BYellow}0.${NC} 返回主菜单\n"

    read -p "请选择 [0-7]: " choice

    case $choice in
        1)
            echo -e "\n当前缓存大小: $(grep 'cache-size' $DNSMASQ_CONFIG | cut -d'=' -f2)"
            read -p "输入新的缓存大小 (默认10000): " cache_size
            if [ -n "$cache_size" ]; then
                sed -i "s/cache-size=.*/cache-size=$cache_size/" $DNSMASQ_CONFIG
                systemctl restart dnsmasq
                echo -e "${BGreen}[成功]${NC} 缓存大小已设置为: $cache_size"
            fi
            ;;
        2)
            echo -e "\n当前最小TTL: $(grep 'min-cache-ttl' $DNSMASQ_CONFIG | cut -d'=' -f2)秒"
            read -p "输入新的最小TTL时间 (秒): " min_ttl
            if [ -n "$min_ttl" ]; then
                sed -i "s/min-cache-ttl=.*/min-cache-ttl=$min_ttl/" $DNSMASQ_CONFIG
                systemctl restart dnsmasq
                echo -e "${BGreen}[成功]${NC} 最小TTL已设置为: ${min_ttl}秒"
            fi
            ;;
        3)
            read -p "输入要添加的监听IP地址: " listen_ip
            if [[ $listen_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                sed -i "/^listen-address=/s/$/,$listen_ip/" $DNSMASQ_CONFIG
                systemctl restart dnsmasq
                echo -e "${BGreen}[成功]${NC} 已添加监听地址: $listen_ip"
            else
                echo -e "${BRed}[错误]${NC} 无效的IP地址"
            fi
            ;;
        4)
            echo -e "\n当前上游DNS服务器:"
            grep "^server=" $DNSMASQ_CONFIG | grep -v "/"
            echo -e "\n输入新的上游DNS服务器 (多个用空格分隔):"
            read -p "DNS服务器: " dns_servers
            if [ -n "$dns_servers" ]; then
                # 删除旧的上游DNS配置
                sed -i '/^server=[0-9]/d' $DNSMASQ_CONFIG
                # 添加新的DNS服务器
                for dns in $dns_servers; do
                    echo "server=$dns" >> $DNSMASQ_CONFIG
                done
                systemctl restart dnsmasq
                echo -e "${BGreen}[成功]${NC} 上游DNS服务器已更新"
            fi
            ;;
        5)
            if grep -q "^log-queries" $DNSMASQ_CONFIG; then
                sed -i 's/^log-queries/#log-queries/' $DNSMASQ_CONFIG
                echo -e "${BYellow}[信息]${NC} 查询日志已禁用"
            else
                sed -i 's/^#log-queries/log-queries/' $DNSMASQ_CONFIG
                echo -e "${BGreen}[信息]${NC} 查询日志已启用"
            fi
            systemctl restart dnsmasq
            ;;
        6)
            systemctl restart dnsmasq
            echo -e "${BGreen}[成功]${NC} DNS缓存已清空"
            ;;
        7)
            setup_cron
            ;;
        0)
            return
            ;;
        *)
            echo -e "${BRed}[错误]${NC} 无效的选择"
            ;;
    esac

    echo -e "\n按任意键返回..."
    read -n 1
}

# 设置定时任务
setup_cron() {
    echo -e "\n${BWhite}设置定时任务:${NC}\n"
    echo -e "  ${BYellow}1.${NC} 每天自动更新流媒体域名列表"
    echo -e "  ${BYellow}2.${NC} 每周自动清理日志"
    echo -e "  ${BYellow}3.${NC} 查看当前定时任务"
    echo -e "  ${BYellow}4.${NC} 删除所有定时任务"
    echo -e "  ${BYellow}0.${NC} 返回\n"

    read -p "请选择 [0-4]: " choice

    case $choice in
        1)
            # 创建更新脚本
            cat > /usr/local/bin/update-proxy-domains.sh <<'EOF'
#!/bin/bash
curl -s -L -o /tmp/proxy-domains.txt https://raw.githubusercontent.com/miyouzi/dnsmasq_sniproxy_install/main/proxy-domains.txt
if [ $? -eq 0 ]; then
    mv /tmp/proxy-domains.txt /etc/dnsmasq.d/proxy-domains.txt
    systemctl reload dnsmasq
fi
EOF
            chmod +x /usr/local/bin/update-proxy-domains.sh

            # 添加到crontab
            (crontab -l 2>/dev/null | grep -v "update-proxy-domains.sh"; echo "0 3 * * * /usr/local/bin/update-proxy-domains.sh > /dev/null 2>&1") | crontab -
            echo -e "${BGreen}[成功]${NC} 已设置每天凌晨3点自动更新域名列表"
            ;;
        2)
            # 创建日志清理脚本
            cat > /usr/local/bin/clean-dns-logs.sh <<EOF
#!/bin/bash
find $LOG_DIR -name "*.log" -size +100M -exec truncate -s 0 {} \;
EOF
            chmod +x /usr/local/bin/clean-dns-logs.sh

            # 添加到crontab
            (crontab -l 2>/dev/null | grep -v "clean-dns-logs.sh"; echo "0 2 * * 0 /usr/local/bin/clean-dns-logs.sh > /dev/null 2>&1") | crontab -
            echo -e "${BGreen}[成功]${NC} 已设置每周日凌晨2点自动清理日志"
            ;;
        3)
            echo -e "\n${BCyan}当前定时任务:${NC}\n"
            crontab -l 2>/dev/null || echo "没有设置定时任务"
            ;;
        4)
            crontab -r 2>/dev/null
            rm -f /usr/local/bin/update-proxy-domains.sh
            rm -f /usr/local/bin/clean-dns-logs.sh
            echo -e "${BYellow}[信息]${NC} 已删除所有定时任务"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${BRed}[错误]${NC} 无效的选择"
            ;;
    esac
}

# 完全卸载
uninstall_all() {
    echo -e "\n${BRed}警告: 这将完全卸载DNS代理服务！${NC}"
    echo -e "确定要继续吗? [y/N]"
    read -r response

    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${BYellow}[信息]${NC} 取消卸载"
        return
    fi

    echo -e "${BGreen}[信息]${NC} 停止服务..."
    systemctl stop dnsmasq sniproxy 2>/dev/null
    systemctl disable dnsmasq sniproxy 2>/dev/null

    echo -e "${BGreen}[信息]${NC} 卸载软件包..."
    if [ "$PKG_MANAGER" == "apt-get" ]; then
        apt-get remove --purge -y dnsmasq sniproxy
    else
        yum remove -y dnsmasq sniproxy
    fi

    echo -e "${BGreen}[信息]${NC} 清理配置文件..."
    rm -rf /etc/dnsmasq.d
    rm -f $DNSMASQ_CONFIG $SNIPROXY_CONFIG
    rm -rf $LOG_DIR
    rm -f /etc/systemd/system/sniproxy.service

    # 恢复resolv.conf
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    # 恢复systemd-resolved
    systemctl enable systemd-resolved 2>/dev/null
    systemctl start systemd-resolved 2>/dev/null

    # 删除定时任务
    crontab -r 2>/dev/null
    rm -f /usr/local/bin/update-proxy-domains.sh
    rm -f /usr/local/bin/clean-dns-logs.sh

    echo -e "${BGreen}[成功]${NC} 卸载完成"
}

# 显示主菜单
show_menu() {
    clear
    local external_ip=$(get_external_ip)

    echo -e "${On_Green}                                                      ${NC}"
    echo -e "${BWhite}         DNS流媒体解锁服务管理系统 v3.0              ${NC}"
    echo -e "${On_Green}                                                      ${NC}"
    echo -e ""
    echo -e "${BCyan}服务器IP:${NC} ${BWhite}${external_ip}${NC}"

    # 显示服务状态
    if systemctl is-active --quiet dnsmasq; then
        echo -e "${BCyan}DNSMasq:${NC} ${BGreen}[运行中]${NC}"
    else
        echo -e "${BCyan}DNSMasq:${NC} ${BRed}[已停止]${NC}"
    fi

    if systemctl is-active --quiet sniproxy; then
        echo -e "${BCyan}SNIProxy:${NC} ${BGreen}[运行中]${NC}"
    else
        echo -e "${BCyan}SNIProxy:${NC} ${BRed}[已停止]${NC}"
    fi

    echo -e "\n${BWhite}============= 主菜单 =============${NC}\n"

    echo -e "${BCyan}安装与配置:${NC}"
    echo -e "  ${BYellow}1.${NC}  完整安装 (DNSMasq + SNIProxy)"
    echo -e "  ${BYellow}2.${NC}  仅安装 DNSMasq"
    echo -e "  ${BYellow}3.${NC}  仅安装 SNIProxy"

    echo -e "\n${BCyan}DNS配置管理:${NC}"
    echo -e "  ${BYellow}4.${NC}  配置流媒体DNS解锁"
    echo -e "  ${BYellow}5.${NC}  添加自定义域名"
    echo -e "  ${BYellow}6.${NC}  批量导入域名"
    echo -e "  ${BYellow}7.${NC}  查看当前配置"

    echo -e "\n${BCyan}服务管理:${NC}"
    echo -e "  ${BYellow}8.${NC}  启动服务"
    echo -e "  ${BYellow}9.${NC}  停止服务"
    echo -e "  ${BYellow}10.${NC} 重启服务"
    echo -e "  ${BYellow}11.${NC} 查看日志"

    echo -e "\n${BCyan}系统管理:${NC}"
    echo -e "  ${BYellow}12.${NC} 高级设置"
    echo -e "  ${BYellow}13.${NC} 更新域名列表"
    echo -e "  ${BYellow}14.${NC} 完全卸载"

    echo -e "\n  ${BYellow}0.${NC}  退出\n"

    echo -e "${BWhite}==================================${NC}\n"
}

# 主函数
main() {
    check_system

    while true; do
        show_menu
        read -p "请选择 [0-14]: " choice

        case $choice in
            0)
                echo -e "\n${BGreen}感谢使用，再见！${NC}\n"
                exit 0
                ;;
            1)
                check_ports
                install_dependencies
                install_dnsmasq
                install_sniproxy
                configure_firewall
                echo -e "\n${BGreen}[成功]${NC} 完整安装完成！"
                echo -e "请将客户端DNS设置为: ${BWhite}$(get_external_ip)${NC}"
                ;;
            2)
                check_ports
                install_dependencies
                install_dnsmasq
                configure_firewall
                ;;
            3)
                check_ports
                install_dependencies
                install_sniproxy
                configure_firewall
                ;;
            4)
                configure_streaming_dns
                ;;
            5)
                add_custom_domain
                ;;
            6)
                import_domains
                ;;
            7)
                show_dns_config
                ;;
            8)
                systemctl start dnsmasq sniproxy
                echo -e "${BGreen}[成功]${NC} 服务已启动"
                ;;
            9)
                systemctl stop dnsmasq sniproxy
                echo -e "${BYellow}[信息]${NC} 服务已停止"
                ;;
            10)
                systemctl restart dnsmasq sniproxy
                echo -e "${BGreen}[成功]${NC} 服务已重启"
                ;;
            11)
                view_logs
                ;;
            12)
                advanced_settings
                ;;
            13)
                if [ -f "$PROXY_DOMAINS_FILE" ]; then
                    curl -s -L -o "${PROXY_DOMAINS_FILE}.tmp" "$PROXY_DOMAINS_URL"
                    if [ $? -eq 0 ]; then
                        mv "${PROXY_DOMAINS_FILE}.tmp" "$PROXY_DOMAINS_FILE"
                        echo -e "${BGreen}[成功]${NC} 域名列表已更新"
                    else
                        echo -e "${BRed}[错误]${NC} 更新失败"
                    fi
                else
                    echo -e "${BYellow}[信息]${NC} 未找到域名列表文件"
                fi
                ;;
            14)
                uninstall_all
                ;;
            *)
                echo -e "${BRed}[错误]${NC} 无效的选择"
                ;;
        esac

        if [ "$choice" != "0" ] && [ "$choice" != "7" ] && [ "$choice" != "11" ]; then
            echo -e "\n按任意键继续..."
            read -n 1
        fi
    done
}

# 运行主程序
main "$@"