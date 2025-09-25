#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}   DNS服务器修复脚本 v1.0${NC}"
echo -e "${BLUE}============================================${NC}\n"

# 步骤1：修复DNS解析
echo -e "${BLUE}[步骤1]${NC} 修复DNS解析..."

# 临时设置DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo -e "${GREEN}✓${NC} DNS已设置为 8.8.8.8 和 1.1.1.1\n"

# 步骤2：检查并停止占用443端口的服务
echo -e "${BLUE}[步骤2]${NC} 检查443端口占用..."

# 查看443端口被谁占用
port_443_info=$(lsof -i :443 | grep LISTEN | head -1)
if [ -n "$port_443_info" ]; then
    echo -e "${YELLOW}警告:${NC} 443端口被占用："
    echo "$port_443_info"

    # 获取进程名
    process_name=$(echo "$port_443_info" | awk '{print $1}')

    echo -e "\n是否停止 ${RED}$process_name${NC} 服务? (y/n): "
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        case $process_name in
            nginx)
                systemctl stop nginx
                systemctl disable nginx
                echo -e "${GREEN}✓${NC} nginx已停止"
                ;;
            apache2)
                systemctl stop apache2
                systemctl disable apache2
                echo -e "${GREEN}✓${NC} apache2已停止"
                ;;
            httpd)
                systemctl stop httpd
                systemctl disable httpd
                echo -e "${GREEN}✓${NC} httpd已停止"
                ;;
            docker-proxy)
                echo -e "${YELLOW}注意:${NC} 检测到Docker容器占用443端口"
                echo "运行以下命令查看容器："
                echo "docker ps --filter 'publish=443'"
                ;;
            *)
                # 尝试通过进程ID杀死
                pid=$(echo "$port_443_info" | awk '{print $2}')
                kill -9 $pid 2>/dev/null
                echo -e "${GREEN}✓${NC} 进程已终止"
                ;;
        esac
    fi
else
    echo -e "${GREEN}✓${NC} 443端口未被占用\n"
fi

# 步骤3：更新软件源
echo -e "${BLUE}[步骤3]${NC} 更新软件源..."
apt-get update > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 软件源更新成功\n"
else
    echo -e "${YELLOW}警告:${NC} 软件源更新失败，继续安装...\n"
fi

# 步骤4：获取外部IP
echo -e "${BLUE}[步骤4]${NC} 获取服务器IP地址..."

# 多种方式获取IP
get_ip_method1() {
    curl -s -4 --connect-timeout 3 https://icanhazip.com 2>/dev/null
}

get_ip_method2() {
    curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null
}

get_ip_method3() {
    curl -s -4 --connect-timeout 3 https://ifconfig.me 2>/dev/null
}

get_ip_method4() {
    curl -s -4 --connect-timeout 3 https://ip.sb 2>/dev/null
}

get_ip_method5() {
    # 从网络接口获取
    ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1
}

# 尝试不同方法获取IP
EXTERNAL_IP=""
for method in get_ip_method1 get_ip_method2 get_ip_method3 get_ip_method4; do
    EXTERNAL_IP=$($method)
    if [[ $EXTERNAL_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
done

# 如果还是获取不到，使用本地IP
if [ -z "$EXTERNAL_IP" ] || [[ ! $EXTERNAL_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EXTERNAL_IP=$(get_ip_method5)
    echo -e "${YELLOW}警告:${NC} 无法获取外网IP，使用本地IP: $EXTERNAL_IP"
else
    echo -e "${GREEN}✓${NC} 服务器IP: $EXTERNAL_IP\n"
fi

# 步骤5：安装必要软件
echo -e "${BLUE}[步骤5]${NC} 安装必要软件..."

# 安装dnsmasq
if ! command -v dnsmasq &> /dev/null; then
    apt-get install -y dnsmasq > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} dnsmasq 安装成功"
    else
        echo -e "${RED}✗${NC} dnsmasq 安装失败"
    fi
else
    echo -e "${GREEN}✓${NC} dnsmasq 已安装"
fi

# 安装sniproxy
if ! command -v sniproxy &> /dev/null; then
    apt-get install -y sniproxy > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} sniproxy 安装成功"
    else
        echo -e "${RED}✗${NC} sniproxy 安装失败"
    fi
else
    echo -e "${GREEN}✓${NC} sniproxy 已安装"
fi

# 步骤6：配置dnsmasq
echo -e "\n${BLUE}[步骤6]${NC} 配置dnsmasq..."

cat > /etc/dnsmasq.conf <<EOF
# 基础配置
user=nobody
no-resolv
no-poll
expand-hosts
listen-address=127.0.0.1,$EXTERNAL_IP
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

# 流媒体域名解析到本服务器
address=/netflix.com/$EXTERNAL_IP
address=/netflix.net/$EXTERNAL_IP
address=/nflximg.com/$EXTERNAL_IP
address=/nflximg.net/$EXTERNAL_IP
address=/nflxvideo.net/$EXTERNAL_IP
address=/disneyplus.com/$EXTERNAL_IP
address=/disney-plus.net/$EXTERNAL_IP
address=/dssott.com/$EXTERNAL_IP
address=/bamgrid.com/$EXTERNAL_IP
address=/youtube.com/$EXTERNAL_IP
address=/googlevideo.com/$EXTERNAL_IP
address=/ytimg.com/$EXTERNAL_IP
address=/ggpht.com/$EXTERNAL_IP
EOF

# 创建日志目录
mkdir -p /var/log/dnsmasq

# 重启dnsmasq
systemctl restart dnsmasq
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} dnsmasq 配置完成并启动"
else
    echo -e "${RED}✗${NC} dnsmasq 启动失败"
fi

# 步骤7：配置sniproxy
echo -e "\n${BLUE}[步骤7]${NC} 配置sniproxy..."

cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

listener 0.0.0.0:80 {
    proto http

    table {
        .* *
    }
}

listener 0.0.0.0:443 {
    proto tls

    table {
        .* *
    }
}
EOF

# 重启sniproxy
systemctl restart sniproxy
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} sniproxy 配置完成并启动"
else
    echo -e "${YELLOW}警告:${NC} sniproxy 启动可能失败（如果443端口仍被占用）"
fi

# 步骤8：配置防火墙
echo -e "\n${BLUE}[步骤8]${NC} 配置防火墙..."

# 检查是否有ufw
if command -v ufw &> /dev/null; then
    ufw allow 53/tcp > /dev/null 2>&1
    ufw allow 53/udp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    echo -e "${GREEN}✓${NC} UFW防火墙规则已添加"
fi

# 使用iptables
if command -v iptables &> /dev/null; then
    iptables -I INPUT -p tcp --dport 53 -j ACCEPT
    iptables -I INPUT -p udp --dport 53 -j ACCEPT
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    echo -e "${GREEN}✓${NC} iptables规则已添加"
fi

# 最终状态检查
echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}   服务状态检查${NC}"
echo -e "${BLUE}============================================${NC}\n"

# 检查dnsmasq状态
if systemctl is-active --quiet dnsmasq; then
    echo -e "DNSMasq: ${GREEN}[运行中]${NC}"
else
    echo -e "DNSMasq: ${RED}[已停止]${NC}"
fi

# 检查sniproxy状态
if systemctl is-active --quiet sniproxy; then
    echo -e "SNIProxy: ${GREEN}[运行中]${NC}"
else
    echo -e "SNIProxy: ${YELLOW}[已停止]${NC} (如果不需要HTTPS代理可以忽略)"
fi

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}   配置信息${NC}"
echo -e "${BLUE}============================================${NC}\n"

echo -e "服务器IP: ${GREEN}$EXTERNAL_IP${NC}"
echo -e "DNS端口: ${GREEN}53${NC}"
echo -e "HTTP端口: ${GREEN}80${NC}"
echo -e "HTTPS端口: ${GREEN}443${NC}"

echo -e "\n${YELLOW}客户端配置说明:${NC}"
echo -e "1. 将设备的DNS服务器设置为: ${GREEN}$EXTERNAL_IP${NC}"
echo -e "2. 测试命令: "
echo -e "   ${BLUE}nslookup netflix.com $EXTERNAL_IP${NC}"
echo -e "   ${BLUE}dig @$EXTERNAL_IP netflix.com${NC}"

echo -e "\n${YELLOW}常用命令:${NC}"
echo -e "查看DNS日志: ${BLUE}tail -f /var/log/syslog | grep dnsmasq${NC}"
echo -e "重启服务: ${BLUE}systemctl restart dnsmasq sniproxy${NC}"
echo -e "查看状态: ${BLUE}systemctl status dnsmasq sniproxy${NC}"

echo -e "\n${GREEN}修复完成！${NC}\n"