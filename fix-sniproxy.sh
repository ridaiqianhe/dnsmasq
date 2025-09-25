#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[信息]${NC} 修复SNIProxy配置..."

# 获取外部IP
get_external_ip() {
    local ip=$(curl -s -4 https://icanhazip.com)
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(curl -s -4 https://api.ipify.org)
    fi
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(curl -s -4 https://ifconfig.me)
    fi
    echo "$ip"
}

# 检查是否为root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误]${NC} 请使用sudo运行此脚本"
    exit 1
fi

# 检查端口占用
echo -e "${BLUE}[信息]${NC} 检查端口占用情况..."
ports_used=false

# 检查80端口
if lsof -i :80 > /dev/null 2>&1; then
    echo -e "${YELLOW}[警告]${NC} 端口80被占用:"
    lsof -i :80 | grep LISTEN
    ports_used=true
fi

# 检查443端口
if lsof -i :443 > /dev/null 2>&1; then
    echo -e "${YELLOW}[警告]${NC} 端口443被占用:"
    lsof -i :443 | grep LISTEN
    ports_used=true
fi

if [ "$ports_used" = true ]; then
    echo -e "${YELLOW}是否停止占用端口的服务? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        # 停止常见的web服务
        systemctl stop nginx 2>/dev/null
        systemctl stop apache2 2>/dev/null
        systemctl stop httpd 2>/dev/null
        echo -e "${GREEN}[成功]${NC} 已尝试停止Web服务"
    fi
fi

# 获取IP地址
EXTERNAL_IP=$(get_external_ip)
if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${RED}[错误]${NC} 无法获取外部IP地址"
    exit 1
fi

echo -e "${GREEN}[信息]${NC} 服务器IP: $EXTERNAL_IP"

# 创建日志目录
mkdir -p /var/log/sniproxy

# 方案1：使用0.0.0.0监听（更通用）
echo -e "${BLUE}[信息]${NC} 配置SNIProxy (方案1: 监听所有接口)..."

cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    syslog daemon
    priority notice
}

resolver {
    nameserver 127.0.0.1
    mode ipv4_only
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

echo -e "${BLUE}[信息]${NC} 测试配置文件..."
# 尝试启动sniproxy
systemctl restart sniproxy

sleep 2

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}[成功]${NC} SNIProxy启动成功（方案1）!"
    systemctl status sniproxy --no-pager
    exit 0
fi

# 方案2：使用具体IP监听
echo -e "${YELLOW}[信息]${NC} 方案1失败，尝试方案2..."

cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    filename /var/log/sniproxy/error.log
    priority notice
}

access_log {
    filename /var/log/sniproxy/access.log
}

resolver {
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    mode ipv4_only
}

listener ${EXTERNAL_IP}:80 {
    proto http

    table {
        .* *
    }
}

listener ${EXTERNAL_IP}:443 {
    proto tls

    table {
        .* *
    }
}
EOF

systemctl restart sniproxy

sleep 2

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}[成功]${NC} SNIProxy启动成功（方案2）!"
    systemctl status sniproxy --no-pager
    exit 0
fi

# 方案3：最小配置
echo -e "${YELLOW}[信息]${NC} 方案2失败，尝试最小配置..."

cat > /etc/sniproxy.conf <<EOF
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

systemctl restart sniproxy

sleep 2

if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}[成功]${NC} SNIProxy启动成功（最小配置）!"
    systemctl status sniproxy --no-pager
else
    echo -e "${RED}[错误]${NC} SNIProxy启动失败，查看详细错误:"
    echo ""
    echo "1. 查看系统日志:"
    echo "   journalctl -u sniproxy -n 50"
    echo ""
    echo "2. 查看sniproxy日志:"
    echo "   tail -n 50 /var/log/sniproxy/error.log"
    echo ""
    echo "3. 手动测试配置:"
    echo "   /usr/sbin/sniproxy -c /etc/sniproxy.conf -f"
    echo ""
    echo "4. 检查端口占用:"
    echo "   lsof -i :80"
    echo "   lsof -i :443"
fi

# 配置防火墙
echo -e "${BLUE}[信息]${NC} 配置防火墙规则..."

# UFW防火墙
if command -v ufw > /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 53/tcp
    ufw allow 53/udp
    echo -e "${GREEN}[成功]${NC} UFW防火墙规则已添加"
fi

# iptables
if command -v iptables > /dev/null; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    iptables -I INPUT -p tcp --dport 53 -j ACCEPT
    iptables -I INPUT -p udp --dport 53 -j ACCEPT
    echo -e "${GREEN}[成功]${NC} iptables规则已添加"
fi

echo ""
echo -e "${BLUE}========== 配置摘要 ==========${NC}"
echo -e "服务器IP: ${GREEN}$EXTERNAL_IP${NC}"
echo -e "DNS端口: ${GREEN}53${NC}"
echo -e "HTTP端口: ${GREEN}80${NC}"
echo -e "HTTPS端口: ${GREEN}443${NC}"
echo ""
echo -e "${YELLOW}客户端配置说明:${NC}"
echo -e "1. 将设备DNS设置为: ${GREEN}$EXTERNAL_IP${NC}"
echo -e "2. 测试命令: nslookup netflix.com $EXTERNAL_IP"
echo ""