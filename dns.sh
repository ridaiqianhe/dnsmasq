#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
purple='\033[0;35m'
plain='\033[0m'

# Bold High Intensity
BIBlack="\033[1;90m"
BIRed="\033[1;91m"
BIGreen="\033[1;92m"
BIYellow="\033[1;93m"
BIBlue="\033[1;94m"
BIPurple="\033[1;95m"
BICyan="\033[1;96m"
BIWhite="\033[1;97m"

# Background Colors
On_Yellow="\033[43m"
On_White="\033[47m"
On_ICyan="\033[0;106m"
On_IWhite="\033[0;107m"
On_IRed="\033[0;101m"

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root权限运行!" && exit 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="/var/log/dns-proxy"
DNSMASQ_CONFIG="/etc/dnsmasq.conf"
SNIPROXY_CONFIG="/etc/sniproxy.conf"
PROXY_DOMAINS_FILE="${SCRIPT_DIR}/proxy-domains.txt"
WHITELIST_CONFIG="/etc/dns-proxy/whitelist.conf"
DNS_PORT=53
HTTP_PORT=80
HTTPS_PORT=443

declare -A dns_domains

# 台湾媒体
dns_domains["TW"]="
kfs.io
kktv-theater.kk.stream
kkbox.com
kkbox.com.tw
kktv.com.tw
kktv.me
litv.tv
ntd-tgc.cdn.hinet.net
cdn.plyr.io
myvideo.net.tw
4gtv.tv
4gtvfreepc-cds.cdn.hinet.net
4gtvfreepcvod-cds.cdn.hinet.net
4gtvpc-cds.cdn.hinet.net
4gtvpcvod-cds.cdn.hinet.net
ofiii.com
ntdofifreepc-tgc.cdn.hinet.net
d3c7rimkq79yfu.cloudfront.net
linetv.tw
cdn.hinet.net
hamivideo.hinet.net
scc.ott.hinet.net
catchplay.com
d2ivmxp5z2ww0n.cloudfront.net
ols-ww100-cp.akamaized.net
tra-www000-cp.akamaized.net
bahamut.com.tw
gamer.com.tw
gamer-cds.cdn.hinet.net
gamer2-cds.cdn.hinet.net
video.friday.tw
"

# 日本媒体
dns_domains["JP"]="
nhk.jp
nhk.or.jp
dmm-extension.com
dmm.co.jp
dmm.com
videomarket.jp
p-smith.com
vmdash-cenc.akamaized.net
img.vm-movie.jp
abema.io
abema.tv
ds-linear-abematv.akamaized.net
linear-abematv.akamaized.net
ds-vod-abematv.akamaized.net
vod-abematv.akamaized.net
vod-playout-abematv.akamaized.net
ameba.jp
hayabusa.io
bucketeer.jp
abema.adx.promo
hayabusa.media
abema-tv.com
dmc.nico
nicovideo.jp
nimg.jp
telasa.jp
kddi-video.com
videopass.jp
d2lmsumy47c8as.cloudfront.net
paravi.jp
unext.jp
nxtv.jp
happyon.jp
hulu.jp
prod.hjholdings.tv
streaks.jp
yb.uncn.jp
hjholdings.jp
tver.jp
edge.api.brightcove.com
gorin.jp
screens-lab.jp
tver.co.jp
dogatch.jp
gyao.yahoo.co.jp
wowow.co.jp
animestore.docomo.ne.jp
fujitv.co.jp
stream.ne.jp
radiko.jp
radionikkei.jp
smartstream.ne.jp
clubdam.com
id.zaq.ne.jp
api-animefesta.iowl.jp
if.lemino.docomo.ne.jp
rakuten.co.jp
cygames.jp
konosubafd.jp
colorfulpalette.org
worldflipper.jp
jujutsuphanpara.jp
mora.jp
music.jp
music-book.jp
data-cloudauthoring.magazine.rakuten.co.jp
"

# 香港媒体
dns_domains["HK"]="
nowe.com
nowestatic.com
now.com
viu.com
viu.now.com
viu.tv
mytvsuper.com
mytvsuperlimited.hb.omtrdc.net
mytvsuperlimited.sc.omtrdc.net
tvb.com
tvb.com.au
tvbc.com.cn
tvbeventpower.com.hk
tvbusa.com
tvbweekly.com
tvmedia.net.au
hoy.tv
tvbanywhere.com
tvbanywhere.com.sg
cognito-identity.us-east-1.amazonaws.com
d1k2us671qcoau.cloudfront.net
d2anahhhmp1ffz.cloudfront.net
dfp6rglgjqszk.cloudfront.net
d3o7oi00quuwqu.cloudfront.net
mobileanalytics.us-east-1.amazonaws.com
"

# Disney 域名
dns_domains["Disney"]="
disney.connections.edge.bamgrid.com
disney.api.edge.bamgrid.com
disney-plus.net
disneyplus.com
dssott.com
disneynow.com
disneystreaming.com
cdn.registerdisney.go.com
"

# Netflix 域名
dns_domains["Netflix"]="
netflix.com
netflix.net
nflximg.com
nflximg.net
nflxvideo.net
nflxext.com
nflxso.net
"

# Amazon Prime Video 域名
dns_domains["Prime"]="
d1v5ir2lpwr8os.cloudfront.net
d22qjgkvxw22r6.cloudfront.net
d25xi40x97liuc.cloudfront.net
d27xxe7juh1us6.cloudfront.net
dmqdd6hw24ucf.cloudfront.net
aiv-cdn.net
aiv-delivery.net
amazonvideo.com
atv-ext-eu.amazon.com
atv-ext-fe.amazon.com
atv-ext.amazon.com
atv-ps-eu.amazon.co.uk
atv-ps-eu.amazon.com
atv-ps-fe.amazon.co.jp
atv-ps-fe.amazon.com
atv-ps.amazon.com
primevideo.com
pv-cdn.net
video.a2z.com
"

# DAZN 域名
dns_domains["DAZN"]="
dazn-api.com
dazn.com
dazndn.com
indazn.com
d151l6v8er5bdm.cloudfront.net
d1sgwhnao7452x.cloudfront.net
dcalivedazn.akamaized.net
dcblivedazn.akamaized.net
"

# HBO/Max 域名
dns_domains["HBO"]="
max.com
hbo.com
hbogo.com
hbomax.com
hbomaxcdn.com
hbonow.com
maxgo.com
discomax.com
"

# AI平台域名
dns_domains["AI"]="
openai.com
chatgpt.com
sora.com
oaistatic.com
oaiusercontent.com
anthropic.com
claude.ai
gemini.google.com
proactivebackend-pa.googleapis.com
aistudio.google.com
alkalimakersuite-pa.clients6.google.com
generativelanguage.googleapis.com
copilot.microsoft.com
"

# Youtube 域名
dns_domains["Youtube"]="
youtube.com
youtubei.googleapis.com
googlevideo.com
ytimg.com
ggpht.com
"

# Google 域名
dns_domains["Google"]="
google.com
googleapis.com
gstatic.com
"

# Instagram 域名
dns_domains["Instagram"]="
instagram.com
cdninstagram.com
"

# TikTok 域名
dns_domains["TikTok"]="
byteoversea.com
ibytedtos.com
ipstatp.com
muscdn.com
musical.ly
tiktok.com
tik-tokapi.com
tiktokcdn.com
tiktokv.com
"

# iQiyi 域名
dns_domains["iQiyi"]="
71.am
iq.com
iqiyi.com
iqiyipic.com
pps.tv
ppsimg.com
qiyi.com
qiyipic.com
qy.net
71.am.com
71edge.com
71edge.net
aianno.cn
aianno.com
aiqiyicloud-mgmt.com
aiqiyicloud.com
aiqiyicloud.net
baiying.com
gitv.cn
gitv.tv
ibkstore.com
iqiyi.demo.uwp
iqiyiedge.com
iqiyiedge.net
jiangbing.cn
ppstream.cn
ppstream.com
ppstream.com.cn
ppstream.net
ppstream.net.cn
ppsurl.com
qiyi.cn
suike.cn
"

# BiliBili 域名
dns_domains["BiliBili"]="
www.bilibili.com
api.bilibili.com
api.biliapi.net
api.biliapi.com
app.bilibili.com
app.biliapi.net
app.biliapi.com
grpc.biliapi.net
bilibili.com
bilibili.tv
bilivideo.com
"

# Steam 域名
dns_domains["Steam"]="
steampowered.com
steamcommunity.com
steamusercontent.com
"

# 韩国媒体
dns_domains["Korea"]="
wavve.com
pooq.co.kr
tving.com
coupangplay.com
naver.com
navercorp.com
pstatic.net
smartmediarep.com
afreecatv.com
kbs.co.kr
jtbc.co.kr
pandalive.co.kr
kocowa.com
"

# 速度测试
dns_domains["speedtest"]="
fast.com
ooklaserver.net
speed.cloudflare.com
speed.dler.io
ip.sb
ip.skk.moe
speedtest.net
"

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
    local services=("systemd-resolved" "bind9" "named" "apache2" "nginx" "httpd")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo -e "[${green}Info${plain}] 停止服务: $service"
            systemctl stop $service
            systemctl disable $service 2>/dev/null
        fi
    done

    echo -e "[${green}Info${plain}] 清理残留进程..."
    pkill -9 sniproxy 2>/dev/null

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

    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf

    $PKG_UPDATE > /dev/null 2>&1

    local packages=("curl" "wget" "lsof" "iptables" "ipset")

    for pkg in "${packages[@]}"; do
        if ! command -v $pkg > /dev/null; then
            echo -e "[${green}Info${plain}] 安装 $pkg..."
            $PKG_MANAGER install -y $pkg > /dev/null 2>&1
        fi
    done
}

# 防火墙白名单管理功能
manage_whitelist() {
    echo -e "\n${blue}======== 防火墙白名单管理 ========${plain}"
    echo "1. 查看当前白名单"
    echo "2. 添加IP到白名单"
    echo "3. 删除IP白名单"
    echo "4. 设置DNS端口白名单"
    echo "5. 清空所有白名单"
    echo "6. 导入白名单列表"
    echo "7. 导出白名单列表"
    echo "0. 返回主菜单"
    echo -e "${blue}====================================${plain}"

    read -p "请选择 [0-7]: " choice

    case $choice in
        0)
            return
            ;;
        1)
            show_whitelist
            ;;
        2)
            add_ip_whitelist
            ;;
        3)
            remove_ip_whitelist
            ;;
        4)
            set_dns_port_whitelist
            ;;
        5)
            clear_whitelist
            ;;
        6)
            import_whitelist
            ;;
        7)
            export_whitelist
            ;;
        *)
            echo -e "[${red}Error${plain}] 无效的选择"
            ;;
    esac
}

show_whitelist() {
    echo -e "\n${green}======== 当前白名单配置 ========${plain}"

    # 创建配置目录
    mkdir -p /etc/dns-proxy

    if [ -f "$WHITELIST_CONFIG" ]; then
        echo -e "${cyan}白名单IP列表:${plain}"
        grep -v "^#" "$WHITELIST_CONFIG" | grep -v "^$" | while read ip; do
            echo "  - $ip"
        done
    else
        echo -e "${yellow}暂无白名单配置${plain}"
    fi

    # 显示iptables规则
    echo -e "\n${cyan}当前防火墙规则:${plain}"

    # 检查是否有DNS白名单链
    if iptables -L DNS_WHITELIST -n 2>/dev/null | grep -q "ACCEPT"; then
        echo -e "${green}DNS端口白名单规则:${plain}"
        iptables -L DNS_WHITELIST -n | grep ACCEPT | while read line; do
            echo "  $line"
        done
    fi

    # 显示ipset列表
    if command -v ipset > /dev/null && ipset list dns_whitelist 2>/dev/null | grep -q "Members:"; then
        echo -e "\n${green}IPSet白名单成员:${plain}"
        ipset list dns_whitelist | grep -A 100 "Members:" | tail -n +2
    fi
}

add_ip_whitelist() {
    echo -e "\n${green}添加IP到白名单${plain}"
    echo "支持格式："
    echo "  - 单个IP: 192.168.1.100"
    echo "  - IP段: 192.168.1.0/24"
    echo "  - 多个IP (逗号分隔): 192.168.1.100,192.168.1.101"

    read -p "请输入要添加的IP地址: " ip_input

    if [ -z "$ip_input" ]; then
        echo -e "[${red}Error${plain}] IP地址不能为空"
        return
    fi

    # 创建配置目录和文件
    mkdir -p /etc/dns-proxy
    touch "$WHITELIST_CONFIG"

    # 创建ipset
    if ! ipset list dns_whitelist 2>/dev/null | grep -q "Name: dns_whitelist"; then
        ipset create dns_whitelist hash:net
    fi

    # 处理多个IP
    IFS=',' read -ra IPS <<< "$ip_input"
    for ip in "${IPS[@]}"; do
        ip=$(echo $ip | xargs)  # 去除空格

        # 验证IP格式
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            # 添加到配置文件
            if ! grep -q "^$ip$" "$WHITELIST_CONFIG"; then
                echo "$ip" >> "$WHITELIST_CONFIG"
                echo -e "[${green}✓${plain}] 添加IP到配置: $ip"
            fi

            # 添加到ipset
            ipset add dns_whitelist "$ip" 2>/dev/null

            # 添加iptables规则
            setup_whitelist_rules "$ip"

            echo -e "[${green}Success${plain}] IP $ip 已添加到白名单"
        else
            echo -e "[${red}Error${plain}] 无效的IP格式: $ip"
        fi
    done
}

remove_ip_whitelist() {
    echo -e "\n${green}删除IP白名单${plain}"

    if [ ! -f "$WHITELIST_CONFIG" ]; then
        echo -e "[${yellow}Warning${plain}] 暂无白名单配置"
        return
    fi

    echo -e "${cyan}当前白名单:${plain}"
    cat "$WHITELIST_CONFIG" | grep -v "^#" | grep -v "^$" | nl

    read -p "请输入要删除的IP或序号: " input

    if [[ $input =~ ^[0-9]+$ ]]; then
        # 按序号删除
        ip=$(sed -n "${input}p" "$WHITELIST_CONFIG")
    else
        ip=$input
    fi

    if [ -n "$ip" ]; then
        # 从配置文件删除
        sed -i "/^$ip$/d" "$WHITELIST_CONFIG"

        # 从ipset删除
        ipset del dns_whitelist "$ip" 2>/dev/null

        # 删除iptables规则
        iptables -D INPUT -p tcp --dport $DNS_PORT -s "$ip" -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport $DNS_PORT -s "$ip" -j ACCEPT 2>/dev/null
        iptables -D INPUT -p tcp --dport $HTTP_PORT -s "$ip" -j ACCEPT 2>/dev/null
        iptables -D INPUT -p tcp --dport $HTTPS_PORT -s "$ip" -j ACCEPT 2>/dev/null

        echo -e "[${green}Success${plain}] IP $ip 已从白名单删除"
    fi
}

set_dns_port_whitelist() {
    echo -e "\n${green}设置DNS端口白名单${plain}"
    echo "当前DNS端口: $DNS_PORT"

    read -p "是否要修改DNS端口? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        read -p "请输入新的DNS端口 (默认53): " new_port
        if [ -n "$new_port" ] && [[ $new_port =~ ^[0-9]+$ ]]; then
            DNS_PORT=$new_port
            echo "DNS_PORT=$DNS_PORT" > /etc/dns-proxy/ports.conf
        fi
    fi

    echo -e "\n选择白名单模式:"
    echo "1. 仅允许白名单IP访问DNS"
    echo "2. 允许所有IP访问DNS"
    echo "3. 自定义规则"

    read -p "请选择 [1-3]: " mode

    case $mode in
        1)
            setup_strict_whitelist
            ;;
        2)
            setup_open_access
            ;;
        3)
            setup_custom_rules
            ;;
        *)
            echo -e "[${red}Error${plain}] 无效的选择"
            ;;
    esac
}

setup_whitelist_rules() {
    local ip=$1

    # 为每个服务端口添加规则
    for port in $DNS_PORT $HTTP_PORT $HTTPS_PORT; do
        # TCP
        if ! iptables -C INPUT -p tcp --dport $port -s "$ip" -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p tcp --dport $port -s "$ip" -j ACCEPT
        fi

        # UDP (仅DNS需要)
        if [ "$port" = "$DNS_PORT" ]; then
            if ! iptables -C INPUT -p udp --dport $port -s "$ip" -j ACCEPT 2>/dev/null; then
                iptables -I INPUT -p udp --dport $port -s "$ip" -j ACCEPT
            fi
        fi
    done
}

setup_strict_whitelist() {
    echo -e "[${green}Info${plain}] 设置严格白名单模式..."

    # 创建白名单链
    iptables -N DNS_WHITELIST 2>/dev/null
    iptables -F DNS_WHITELIST

    # 读取白名单并添加规则
    if [ -f "$WHITELIST_CONFIG" ]; then
        while read ip; do
            if [ -n "$ip" ] && [[ ! "$ip" =~ ^# ]]; then
                iptables -A DNS_WHITELIST -s "$ip" -j ACCEPT
                echo -e "[${green}✓${plain}] 允许IP: $ip"
            fi
        done < "$WHITELIST_CONFIG"
    fi

    # 默认拒绝其他
    iptables -A DNS_WHITELIST -j DROP

    # 将链应用到INPUT
    iptables -D INPUT -p tcp --dport $DNS_PORT -j DNS_WHITELIST 2>/dev/null
    iptables -D INPUT -p udp --dport $DNS_PORT -j DNS_WHITELIST 2>/dev/null
    iptables -I INPUT -p tcp --dport $DNS_PORT -j DNS_WHITELIST
    iptables -I INPUT -p udp --dport $DNS_PORT -j DNS_WHITELIST

    echo -e "[${green}Success${plain}] 严格白名单模式已启用"
}

setup_open_access() {
    echo -e "[${green}Info${plain}] 设置开放访问模式..."

    # 删除白名单链
    iptables -D INPUT -p tcp --dport $DNS_PORT -j DNS_WHITELIST 2>/dev/null
    iptables -D INPUT -p udp --dport $DNS_PORT -j DNS_WHITELIST 2>/dev/null
    iptables -F DNS_WHITELIST 2>/dev/null
    iptables -X DNS_WHITELIST 2>/dev/null

    # 允许所有访问
    iptables -I INPUT -p tcp --dport $DNS_PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $DNS_PORT -j ACCEPT
    iptables -I INPUT -p tcp --dport $HTTP_PORT -j ACCEPT
    iptables -I INPUT -p tcp --dport $HTTPS_PORT -j ACCEPT

    echo -e "[${green}Success${plain}] 开放访问模式已启用"
}

setup_custom_rules() {
    echo -e "\n${green}自定义防火墙规则${plain}"
    echo "示例规则:"
    echo "  1. 允许特定网段: iptables -I INPUT -p tcp --dport 53 -s 192.168.1.0/24 -j ACCEPT"
    echo "  2. 限制连接数: iptables -I INPUT -p tcp --dport 53 -m connlimit --connlimit-above 10 -j DROP"
    echo "  3. 限速: iptables -I INPUT -p udp --dport 53 -m limit --limit 100/s -j ACCEPT"

    read -p "请输入自定义规则 (或按Enter跳过): " custom_rule

    if [ -n "$custom_rule" ]; then
        eval "$custom_rule"
        if [ $? -eq 0 ]; then
            echo -e "[${green}Success${plain}] 自定义规则已应用"

            # 保存到配置
            echo "# Custom rule: $(date)" >> /etc/dns-proxy/custom_rules.sh
            echo "$custom_rule" >> /etc/dns-proxy/custom_rules.sh
        else
            echo -e "[${red}Error${plain}] 规则应用失败"
        fi
    fi
}

clear_whitelist() {
    echo -e "[${yellow}Warning${plain}] 确定要清空所有白名单吗? [y/N]"
    read -r response

    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        # 清空配置文件
        > "$WHITELIST_CONFIG"

        # 清空ipset
        ipset flush dns_whitelist 2>/dev/null
        ipset destroy dns_whitelist 2>/dev/null

        # 删除相关iptables规则
        iptables -F DNS_WHITELIST 2>/dev/null
        iptables -X DNS_WHITELIST 2>/dev/null

        echo -e "[${green}Success${plain}] 所有白名单已清空"
    fi
}

import_whitelist() {
    echo -e "\n${green}导入白名单列表${plain}"
    read -p "请输入白名单文件路径: " filepath

    if [ ! -f "$filepath" ]; then
        echo -e "[${red}Error${plain}] 文件不存在: $filepath"
        return
    fi

    mkdir -p /etc/dns-proxy

    # 备份现有配置
    if [ -f "$WHITELIST_CONFIG" ]; then
        cp "$WHITELIST_CONFIG" "${WHITELIST_CONFIG}.bak"
    fi

    # 导入新配置
    while read ip; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            echo "$ip" >> "$WHITELIST_CONFIG"
            ipset add dns_whitelist "$ip" 2>/dev/null
            setup_whitelist_rules "$ip"
            echo -e "[${green}✓${plain}] 导入IP: $ip"
        fi
    done < "$filepath"

    echo -e "[${green}Success${plain}] 白名单导入完成"
}

export_whitelist() {
    echo -e "\n${green}导出白名单列表${plain}"

    if [ ! -f "$WHITELIST_CONFIG" ]; then
        echo -e "[${yellow}Warning${plain}] 暂无白名单配置"
        return
    fi

    local export_file="/tmp/dns_whitelist_$(date +%Y%m%d_%H%M%S).txt"
    cp "$WHITELIST_CONFIG" "$export_file"

    echo -e "[${green}Success${plain}] 白名单已导出到: $export_file"
    echo -e "${cyan}文件内容:${plain}"
    cat "$export_file"
}

save_iptables_rules() {
    echo -e "[${green}Info${plain}] 保存防火墙规则..."

    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        # Debian/Ubuntu系统
        if command -v netfilter-persistent > /dev/null; then
            netfilter-persistent save
        else
            $PKG_MANAGER install -y iptables-persistent
            netfilter-persistent save
        fi
    elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
        # CentOS/RHEL系统
        service iptables save
    fi

    echo -e "[${green}Success${plain}] 防火墙规则已保存"
}

configure_dnsmasq_advanced() {
    echo -e "\n${blue}======== 高级DNSMasq配置 ========${plain}"
    echo "1. 配置流媒体DNS"
    echo "2. 自定义DNS规则"
    echo "3. 配置上游DNS"
    echo "4. 配置DNS缓存"
    echo "5. 查看DNS日志"
    echo "0. 返回主菜单"
    echo -e "${blue}====================================${plain}"

    read -p "请选择 [0-5]: " choice

    case $choice in
        0)
            return
            ;;
        1)
            configure_streaming_dns
            ;;
        2)
            custom_dns_rules
            ;;
        3)
            configure_upstream_dns
            ;;
        4)
            configure_dns_cache
            ;;
        5)
            view_dns_logs
            ;;
        *)
            echo -e "[${red}Error${plain}] 无效的选择"
            ;;
    esac
}

configure_streaming_dns() {
    echo -e "\n${BIWhite}请选择要配置的流媒体服务:${plain}"
    echo -e "${BIYellow}1.${plain} 台湾媒体 (TW)"
    echo -e "${BIBlue}2.${plain} 日本媒体 (JP)"
    echo -e "${BIYellow}3.${plain} 香港媒体 (HK)"
    echo -e "${BIBlue}4.${plain} Disney+"
    echo -e "${BIYellow}5.${plain} Netflix"
    echo -e "${BIBlue}6.${plain} Amazon Prime"
    echo -e "${BIYellow}7.${plain} DAZN"
    echo -e "${BIBlue}8.${plain} HBO/Max"
    echo -e "${BIYellow}9.${plain} AI平台"
    echo -e "${BIBlue}10.${plain} Youtube"
    echo -e "${BIYellow}11.${plain} Google"
    echo -e "${BIBlue}12.${plain} Instagram"
    echo -e "${BIYellow}13.${plain} TikTok"
    echo -e "${BIBlue}14.${plain} iQiyi"
    echo -e "${BIYellow}15.${plain} BiliBili"
    echo -e "${BIBlue}16.${plain} Steam"
    echo -e "${BIYellow}17.${plain} 韩国媒体"
    echo -e "${BIBlue}18.${plain} 速度测试"
    echo -e "${BIYellow}0.${plain} 返回"

    read -p "请选择 [0-18]: " region_choice

    if [ "$region_choice" == "0" ]; then
        return
    fi

    echo "输入DNS服务器IP (例如: 8.8.8.8) 或使用本机IP (输入 'local'):"
    read dns_ip

    if [ "$dns_ip" == "local" ]; then
        dns_ip=$(get_external_ip)
    fi

    case $region_choice in
        1) selected_region="TW";;
        2) selected_region="JP";;
        3) selected_region="HK";;
        4) selected_region="Disney";;
        5) selected_region="Netflix";;
        6) selected_region="Prime";;
        7) selected_region="DAZN";;
        8) selected_region="HBO";;
        9) selected_region="AI";;
        10) selected_region="Youtube";;
        11) selected_region="Google";;
        12) selected_region="Instagram";;
        13) selected_region="TikTok";;
        14) selected_region="iQiyi";;
        15) selected_region="BiliBili";;
        16) selected_region="Steam";;
        17) selected_region="Korea";;
        18) selected_region="speedtest";;
        *) echo -e "[${red}Error${plain}] 无效的选择"; return;;
    esac

    # 删除旧配置
    for domain in ${dns_domains[$selected_region]}; do
        sed -i "/server=\/$domain\//d" "$DNSMASQ_CONFIG"
        sed -i "/address=\/$domain\//d" "$DNSMASQ_CONFIG"
    done

    # 添加新配置
    if [ -n "$dns_ip" ]; then
        echo -e "\n# $selected_region Streaming Services" >> "$DNSMASQ_CONFIG"
        for domain in ${dns_domains[$selected_region]}; do
            if [ -n "$domain" ]; then
                echo "address=/$domain/$dns_ip" >> "$DNSMASQ_CONFIG"
            fi
        done

        systemctl restart dnsmasq
        echo -e "[${green}Success${plain}] $selected_region 流媒体DNS已配置为: $dns_ip"
    fi
}

custom_dns_rules() {
    echo -e "\n${green}自定义DNS规则${plain}"
    echo "1. 添加域名解析规则"
    echo "2. 添加域名屏蔽规则"
    echo "3. 查看现有规则"
    echo "4. 删除规则"
    echo "0. 返回"

    read -p "请选择 [0-4]: " choice

    case $choice in
        0)
            return
            ;;
        1)
            read -p "输入域名 (例: example.com): " domain
            read -p "输入IP地址: " ip
            echo "address=/$domain/$ip" >> "$DNSMASQ_CONFIG"
            systemctl restart dnsmasq
            echo -e "[${green}Success${plain}] 规则已添加"
            ;;
        2)
            read -p "输入要屏蔽的域名: " domain
            echo "address=/$domain/127.0.0.1" >> "$DNSMASQ_CONFIG"
            systemctl restart dnsmasq
            echo -e "[${green}Success${plain}] 域名已屏蔽"
            ;;
        3)
            echo -e "${cyan}当前自定义规则:${plain}"
            grep -E "^address=|^server=" "$DNSMASQ_CONFIG" | tail -20
            ;;
        4)
            read -p "输入要删除的域名: " domain
            sed -i "/\/$domain\//d" "$DNSMASQ_CONFIG"
            systemctl restart dnsmasq
            echo -e "[${green}Success${plain}] 规则已删除"
            ;;
    esac
}

view_dns_logs() {
    echo -e "\n${cyan}最近的DNS查询日志:${plain}"

    if [ -f /var/log/dnsmasq.log ]; then
        tail -n 50 /var/log/dnsmasq.log
    else
        echo -e "[${yellow}Warning${plain}] 日志文件不存在"
        echo "正在启用DNS日志..."
        echo "log-queries" >> "$DNSMASQ_CONFIG"
        echo "log-facility=/var/log/dnsmasq.log" >> "$DNSMASQ_CONFIG"
        systemctl restart dnsmasq
    fi
}

install_dnsmasq() {
    external_ip=$(get_external_ip)
    echo -e "[${green}Info${plain}] 安装 dnsmasq..."
    echo -e "[${green}Info${plain}] 服务器IP: ${external_ip}"

    # 停止systemd-resolved
    systemctl stop systemd-resolved 2>/dev/null
    systemctl disable systemd-resolved 2>/dev/null

    # 修复resolv.conf
    chattr -i /etc/resolv.conf 2>/dev/null
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
options single-request-reopen
EOF
    chattr +i /etc/resolv.conf

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

# 国内DNS
server=/cn/223.5.5.5
server=/cn/119.29.29.29

# 日志配置
log-facility=/var/log/dnsmasq.log
# log-queries  # 取消注释以记录所有查询

EOF

    mkdir -p $LOG_DIR
    touch /var/log/dnsmasq.log
    chown nobody:nogroup /var/log/dnsmasq.log

    systemctl unmask dnsmasq
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

    echo -e "[${green}Info${plain}] 清理残留进程..."
    systemctl stop sniproxy 2>/dev/null
    systemctl kill -s KILL sniproxy 2>/dev/null

    for pid in $(ps aux | grep '[s]niproxy' | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null
    done

    pkill -9 sniproxy 2>/dev/null
    killall -9 sniproxy 2>/dev/null

    rm -f /var/run/sniproxy.pid /run/sniproxy.pid

    sleep 2

    $PKG_MANAGER install -y sniproxy > /dev/null 2>&1

    echo -e "[${green}Info${plain}] 配置 sniproxy..."

    cat > $SNIPROXY_CONFIG <<'EOF'
user daemon
pidfile /run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listener 0.0.0.0:80 {
    proto http
    table hosts
}

listener 0.0.0.0:443 {
    proto tls
    table hosts
}

table hosts {
    .* *
}
EOF

    rm -rf /etc/systemd/system/sniproxy.service.d/

    systemctl daemon-reload
    systemctl enable sniproxy
    systemctl restart sniproxy

    sleep 2

    if systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] sniproxy 安装并启动成功"
        echo -e "[${green}Info${plain}] SNIProxy监听端口:"
        ss -tuln | grep -E ':80|:443' | grep LISTEN
    else
        echo -e "[${yellow}Warning${plain}] sniproxy 服务状态异常"

        if ps aux | grep -q '[s]niproxy'; then
            echo -e "[${green}Info${plain}] SNIProxy进程已运行"
            ps aux | grep '[s]niproxy' | head -2
        else
            echo -e "[${red}Error${plain}] SNIProxy启动失败"
            journalctl -u sniproxy -n 10 --no-pager
        fi
    fi
}

configure_firewall() {
    echo -e "[${green}Info${plain}] 配置防火墙规则..."

    if command -v ufw > /dev/null; then
        ufw allow $DNS_PORT/tcp > /dev/null 2>&1
        ufw allow $DNS_PORT/udp > /dev/null 2>&1
        ufw allow $HTTP_PORT/tcp > /dev/null 2>&1
        ufw allow $HTTPS_PORT/tcp > /dev/null 2>&1
        echo -e "[${green}Success${plain}] UFW防火墙规则已配置"
    elif command -v firewall-cmd > /dev/null; then
        firewall-cmd --permanent --add-port=$DNS_PORT/tcp > /dev/null 2>&1
        firewall-cmd --permanent --add-port=$DNS_PORT/udp > /dev/null 2>&1
        firewall-cmd --permanent --add-port=$HTTP_PORT/tcp > /dev/null 2>&1
        firewall-cmd --permanent --add-port=$HTTPS_PORT/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        echo -e "[${green}Success${plain}] Firewalld规则已配置"
    else
        iptables -I INPUT -p tcp --dport $DNS_PORT -j ACCEPT
        iptables -I INPUT -p udp --dport $DNS_PORT -j ACCEPT
        iptables -I INPUT -p tcp --dport $HTTP_PORT -j ACCEPT
        iptables -I INPUT -p tcp --dport $HTTPS_PORT -j ACCEPT
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
    echo -e "DNS端口: ${green}${DNS_PORT}${plain}"
    echo -e "HTTP端口: ${green}${HTTP_PORT}${plain}"
    echo -e "HTTPS端口: ${green}${HTTPS_PORT}${plain}"

    echo -e "\n${blue}======== 已配置的流媒体服务 ========${plain}"

    # 检查各个服务的DNS配置
    for service in "Netflix" "Disney" "Youtube" "Prime" "HBO"; do
        if grep -q "${service,,}" "$DNSMASQ_CONFIG" 2>/dev/null; then
            echo -e "${green}✓${plain} $service"
        fi
    done

    echo -e "\n${blue}======== 客户端配置 ========${plain}"
    echo -e "将设备的DNS服务器设置为: ${green}${external_ip}${plain}"

    echo -e "\n${blue}======== 测试命令 ========${plain}"
    echo -e "nslookup netflix.com ${external_ip}"
    echo -e "dig @${external_ip} youtube.com"

    # 显示白名单信息
    if [ -f "$WHITELIST_CONFIG" ] && [ -s "$WHITELIST_CONFIG" ]; then
        echo -e "\n${blue}======== 白名单状态 ========${plain}"
        local count=$(wc -l < "$WHITELIST_CONFIG")
        echo -e "已配置白名单IP数: ${green}${count}${plain}"
    fi
}

restart_services() {
    echo -e "[${green}Info${plain}] 重启服务..."

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

    echo -e "[${green}Info${plain}] 停止所有服务..."

    systemctl stop dnsmasq 2>/dev/null
    systemctl stop sniproxy 2>/dev/null
    systemctl disable dnsmasq 2>/dev/null
    systemctl disable sniproxy 2>/dev/null

    pkill -9 dnsmasq 2>/dev/null
    pkill -9 sniproxy 2>/dev/null
    killall -9 sniproxy 2>/dev/null
    killall -9 dnsmasq 2>/dev/null

    echo -e "[${green}Info${plain}] 卸载软件包..."
    if [ "$PKG_MANAGER" == "apt-get" ]; then
        apt-get remove --purge -y dnsmasq sniproxy dnsmasq-base
        apt-get autoremove -y
    else
        yum remove -y dnsmasq sniproxy
        yum autoremove -y
    fi

    echo -e "[${green}Info${plain}] 清理配置文件..."

    rm -f /etc/dnsmasq.conf
    rm -f /etc/sniproxy.conf
    rm -rf /etc/dnsmasq.d
    rm -rf /etc/dns-proxy

    rm -rf /var/log/dnsmasq*
    rm -rf /var/log/sniproxy*
    rm -rf /var/log/dns-proxy

    rm -f /var/run/dnsmasq.pid
    rm -f /var/run/sniproxy.pid
    rm -f /run/sniproxy.pid

    rm -f /etc/systemd/system/sniproxy.service
    rm -f /etc/systemd/system/dnsmasq.service
    rm -f /lib/systemd/system/sniproxy.service
    rm -f /lib/systemd/system/dnsmasq.service
    systemctl daemon-reload

    echo -e "[${green}Info${plain}] 恢复系统DNS设置..."
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF

    if systemctl list-unit-files | grep -q systemd-resolved; then
        systemctl enable systemd-resolved 2>/dev/null
        systemctl start systemd-resolved 2>/dev/null
    fi

    # 清理防火墙规则
    echo -e "[${green}Info${plain}] 清理防火墙规则..."
    iptables -F DNS_WHITELIST 2>/dev/null
    iptables -X DNS_WHITELIST 2>/dev/null
    ipset destroy dns_whitelist 2>/dev/null

    echo -e "[${green}Success${plain}] 卸载完成！"
}

fix_sniproxy() {
    echo -e "[${green}Info${plain}] 修复SNIProxy..."

    systemctl stop sniproxy 2>/dev/null
    systemctl kill -s KILL sniproxy 2>/dev/null

    echo -e "[${green}Info${plain}] 清理所有SNIProxy进程..."
    for pid in $(ps aux | grep '[s]niproxy' | awk '{print $2}'); do
        echo -e "  杀死进程: PID $pid"
        kill -9 $pid 2>/dev/null
    done

    rm -f /var/run/sniproxy.pid /run/sniproxy.pid
    rm -rf /etc/systemd/system/sniproxy.service.d/

    sleep 2

    if ps aux | grep -q '[s]niproxy'; then
        echo -e "[${yellow}Warning${plain}] 仍有SNIProxy进程残留"
    else
        echo -e "[${green}✓${plain}] 所有SNIProxy进程已清理"
    fi

    echo -e "[${green}Info${plain}] 检查端口占用..."
    port_80_used=false
    port_443_used=false

    if lsof -i :80 | grep -q LISTEN; then
        echo -e "[${yellow}Warning${plain}] 80端口被占用:"
        lsof -i :80 | grep LISTEN | head -2
        port_80_used=true
    else
        echo -e "[${green}✓${plain}] 80端口可用"
    fi

    if lsof -i :443 | grep -q LISTEN; then
        echo -e "[${yellow}Warning${plain}] 443端口被占用:"
        lsof -i :443 | grep LISTEN | head -2
        port_443_used=true
    else
        echo -e "[${green}✓${plain}] 443端口可用"
    fi

    echo -e "[${green}Info${plain}] 创建配置文件..."
    cat > $SNIPROXY_CONFIG <<'EOF'
user daemon
pidfile /run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listener 0.0.0.0:80 {
    proto http
    table hosts
}

listener 0.0.0.0:443 {
    proto tls
    table hosts
}

table hosts {
    .* *
}
EOF

    systemctl daemon-reload
    systemctl enable sniproxy
    systemctl start sniproxy

    sleep 2

    if systemctl is-active --quiet sniproxy; then
        echo -e "[${green}Success${plain}] SNIProxy修复成功!"

        echo -e "\n[${green}服务状态:${plain}]"
        systemctl status sniproxy --no-pager | head -10

        echo -e "\n[${green}监听端口:${plain}]"
        ss -tuln | grep -E ':80|:443'
    else
        echo -e "[${yellow}Warning${plain}] SNIProxy服务未正常运行"

        if ps aux | grep -q '[s]niproxy'; then
            echo -e "[${green}Info${plain}] 但SNIProxy进程已存在并运行"
            ps aux | grep '[s]niproxy'
        else
            echo -e "[${red}Error${plain}] SNIProxy启动失败"
            echo -e "\n错误信息:"
            journalctl -u sniproxy -n 15 --no-pager
        fi
    fi
}

show_menu() {
    clear
    echo -e ""
    echo -e "  ${On_Yellow}DNS流媒体解锁服务 v3.0 (防火墙增强版) ${plain}"
    echo -e "  ${BIWhite} /\_/\ ${plain}"
    echo -e "  ${BIWhite}( o.o )${plain}"
    echo -e "  ${BIWhite} > ^ <${plain}"
    echo -e "${On_ICyan}                                                      ${plain}"
    echo -e ""

    # 显示当前状态
    external_ip=$(get_external_ip)
    echo -e "${BICyan}服务器IP: ${BIWhite}${external_ip}${plain}"

    if systemctl is-active --quiet dnsmasq; then
        echo -e "${BICyan}DNSMasq: ${BIGreen}[运行中]${plain}"
    else
        echo -e "${BICyan}DNSMasq: ${BIRed}[已停止]${plain}"
    fi

    if systemctl is-active --quiet sniproxy; then
        echo -e "${BICyan}SNIProxy: ${BIGreen}[运行中]${plain}"
    else
        echo -e "${BICyan}SNIProxy: ${BIRed}[已停止]${plain}"
    fi

    if [ -f "$WHITELIST_CONFIG" ] && [ -s "$WHITELIST_CONFIG" ]; then
        local count=$(wc -l < "$WHITELIST_CONFIG")
        echo -e "${BICyan}白名单IP: ${BIWhite}${count}个${plain}"
    fi

    echo -e ""
    echo -e "${On_IWhite}                                                      ${plain}"
    echo -e ""
    echo -e "${BIWhite}主要功能:${plain}"
    echo -e "${BIYellow}1.${plain} ${green}完整安装（DNSMasq + SNIProxy）${plain}"
    echo -e "${BIYellow}2.${plain} ${green}配置流媒体DNS解锁${plain}"
    echo -e "${BIYellow}3.${plain} ${green}防火墙白名单管理${plain}"
    echo -e "${BIYellow}4.${plain} ${green}高级DNS配置${plain}"
    echo -e ""
    echo -e "${BIWhite}服务管理:${plain}"
    echo -e "${BIYellow}5.${plain} ${cyan}查看服务状态${plain}"
    echo -e "${BIYellow}6.${plain} ${cyan}重启服务${plain}"
    echo -e "${BIYellow}7.${plain} ${cyan}修复SNIProxy${plain}"
    echo -e ""
    echo -e "${BIWhite}其他选项:${plain}"
    echo -e "${BIYellow}8.${plain} ${yellow}仅安装DNSMasq${plain}"
    echo -e "${BIYellow}9.${plain} ${yellow}仅安装SNIProxy${plain}"
    echo -e "${BIRed}10.${plain} ${On_IRed}卸载所有组件${plain}"
    echo -e "${BIYellow}0.${plain} 退出"
    echo -e "${On_IWhite}                                                      ${plain}"
}

main() {
    check_system

    if [ $# -eq 0 ]; then
        while true; do
            show_menu
            read -p "请选择 [0-10]: " choice

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
                    configure_streaming_dns
                    ;;
                3)
                    manage_whitelist
                    ;;
                4)
                    configure_dnsmasq_advanced
                    ;;
                5)
                    show_status
                    ;;
                6)
                    restart_services
                    ;;
                7)
                    fix_sniproxy
                    ;;
                8)
                    check_ports
                    install_dependencies
                    install_dnsmasq
                    configure_firewall
                    show_status
                    ;;
                9)
                    check_ports
                    install_dependencies
                    install_sniproxy
                    configure_firewall
                    show_status
                    ;;
                10)
                    uninstall_all
                    ;;
                *)
                    echo -e "[${red}Error${plain}] 无效的选择"
                    ;;
            esac

            echo -e "\n按Enter键继续..."
            read
        done
    else
        # 命令行参数处理
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
                echo "  -w, --whitelist   管理白名单"
                echo "  -d, --dns         配置流媒体DNS"
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
            -w|--whitelist)
                manage_whitelist
                ;;
            -d|--dns)
                configure_streaming_dns
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