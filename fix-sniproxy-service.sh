#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}  SNIProxy 服务修复脚本${NC}"
echo -e "${BLUE}======================================${NC}\n"

# 1. 显示当前状态
echo -e "${BLUE}[1/6]${NC} 检查当前状态..."

# 查看进程
echo -e "${YELLOW}当前SNIProxy进程:${NC}"
ps aux | grep '[s]niproxy'

# 查看端口
echo -e "\n${YELLOW}端口占用情况:${NC}"
lsof -i :80 | head -3
lsof -i :443 | head -3

# 2. 停止所有相关进程
echo -e "\n${BLUE}[2/6]${NC} 停止所有SNIProxy进程..."

# 停止systemd服务
systemctl stop sniproxy 2>/dev/null

# 使用systemctl kill
systemctl kill -s KILL sniproxy 2>/dev/null

# 获取所有sniproxy进程PID并杀死
for pid in $(ps aux | grep '[s]niproxy' | awk '{print $2}'); do
    echo -e "杀死进程: PID $pid"
    kill -9 $pid 2>/dev/null
done

# 清理PID文件
rm -f /var/run/sniproxy.pid

sleep 2

# 3. 验证进程已清理
echo -e "\n${BLUE}[3/6]${NC} 验证进程清理..."
if ps aux | grep -q '[s]niproxy'; then
    echo -e "${RED}警告: 仍有SNIProxy进程残留${NC}"
    ps aux | grep '[s]niproxy'
else
    echo -e "${GREEN}✓ 所有SNIProxy进程已清理${NC}"
fi

# 4. 创建正确的配置文件
echo -e "\n${BLUE}[4/6]${NC} 创建配置文件..."

cat > /etc/sniproxy.conf <<'EOF'
user daemon
pidfile /var/run/sniproxy.pid

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

echo -e "${GREEN}✓ 配置文件已创建${NC}"

# 5. 修复systemd服务文件
echo -e "\n${BLUE}[5/6]${NC} 修复systemd服务..."

# 创建自定义服务文件
cat > /etc/systemd/system/sniproxy.service <<'EOF'
[Unit]
Description=SNI Proxy Service
After=network.target

[Service]
Type=forking
PIDFile=/var/run/sniproxy.pid
ExecStartPre=/bin/rm -f /var/run/sniproxy.pid
ExecStart=/usr/sbin/sniproxy -c /etc/sniproxy.conf
ExecStop=/bin/kill -TERM $MAINPID
ExecStopPost=/bin/rm -f /var/run/sniproxy.pid
KillMode=control-group
KillSignal=SIGKILL
TimeoutStopSec=5
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd
systemctl daemon-reload

echo -e "${GREEN}✓ Systemd服务已修复${NC}"

# 6. 启动服务
echo -e "\n${BLUE}[6/6]${NC} 启动SNIProxy服务..."

systemctl enable sniproxy
systemctl start sniproxy

sleep 2

# 检查状态
if systemctl is-active --quiet sniproxy; then
    echo -e "${GREEN}✓ SNIProxy服务启动成功!${NC}"

    echo -e "\n${GREEN}服务状态:${NC}"
    systemctl status sniproxy --no-pager | head -10

    echo -e "\n${GREEN}监听端口:${NC}"
    ss -tuln | grep -E ':80|:443'

    echo -e "\n${GREEN}进程信息:${NC}"
    ps aux | grep '[s]niproxy'
else
    echo -e "${RED}✗ SNIProxy服务启动失败${NC}"

    echo -e "\n${YELLOW}错误信息:${NC}"
    journalctl -u sniproxy -n 20 --no-pager

    echo -e "\n${YELLOW}尝试手动启动测试:${NC}"
    /usr/sbin/sniproxy -c /etc/sniproxy.conf -f &
    sleep 2

    if ps aux | grep -q '[s]niproxy'; then
        echo -e "${GREEN}手动启动成功，服务文件可能有问题${NC}"

        # 杀死手动启动的进程
        pkill -f "sniproxy -c"

        # 尝试使用原始服务文件
        rm -f /etc/systemd/system/sniproxy.service
        systemctl daemon-reload
        systemctl start sniproxy

        if systemctl is-active --quiet sniproxy; then
            echo -e "${GREEN}使用原始服务文件启动成功${NC}"
        fi
    else
        echo -e "${RED}配置文件可能有问题${NC}"
        echo -e "请检查: /etc/sniproxy.conf"
    fi
fi

echo -e "\n${BLUE}======================================${NC}"
echo -e "${GREEN}  修复完成${NC}"
echo -e "${BLUE}======================================${NC}"

# 显示最终状态
echo -e "\n${YELLOW}最终检查:${NC}"
echo -e "服务状态: $(systemctl is-active sniproxy)"
echo -e "进程数量: $(ps aux | grep '[s]niproxy' | wc -l)"
echo -e "80端口: $(lsof -i :80 2>/dev/null | grep -c LISTEN)"
echo -e "443端口: $(lsof -i :443 2>/dev/null | grep -c LISTEN)"

echo -e "\n${GREEN}DNS服务器IP: $(curl -s ip.sb || hostname -I | awk '{print $1}')${NC}"