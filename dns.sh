#!/bin/bash

# 检查是否有root权限
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本"
  exit 1
fi

# 检测80和443端口是否被占用
function check_ports() {
  for port in 80 443; do
    if lsof -i :$port > /dev/null; then
      echo "端口 $port 被占用，无法继续安装。"
      exit 1
    fi
  done
}

# 安装 dnsmasq 和 sniproxy
function install_services() {
  echo "安装 dnsmasq 和 sniproxy..."
  apt-get update
  apt-get install -y dnsmasq sniproxy

  # 配置 dnsmasq
  echo "配置 dnsmasq..."
  echo "listen-address=127.0.0.1" >> /etc/dnsmasq.conf
  echo "address=/#/127.0.0.1" >> /etc/dnsmasq.conf

  # 配置 sniproxy
  echo "配置 sniproxy..."
  cat <<EOF > /etc/sniproxy.conf
user nobody
pidfile /var/run/sniproxy.pid

listen 80 {
    proto http
    table {
        .* *
    }
}

listen 443 {
    proto tls
    table {
        .* *
    }
}

table {
    .* 127.0.0.1:8080
}
EOF

  # 重启服务
  echo "重启 dnsmasq 和 sniproxy..."
  systemctl restart dnsmasq
  systemctl restart sniproxy

  echo "dnsmasq 和 sniproxy 安装并配置完成。"
}

# 卸载 dnsmasq 和 sniproxy
function uninstall_services() {
  echo "卸载 dnsmasq 和 sniproxy..."
  apt-get remove --purge -y dnsmasq sniproxy
  rm -f /etc/dnsmasq.conf
  rm -f /etc/sniproxy.conf
  echo "dnsmasq 和 sniproxy 已卸载。"
}

# 主菜单
function main_menu() {
  echo "选择操作："
  echo "1) 安装并配置 dnsmasq 和 sniproxy"
  echo "2) 卸载 dnsmasq 和 sniproxy"
  echo "3) 退出"
  read -p "输入选择: " choice

  case $choice in
    1)
      check_ports
      install_services
      ;;
    2)
      uninstall_services
      ;;
    3)
      exit 0
      ;;
    *)
      echo "无效选择，请重试。"
      main_menu
      ;;
  esac
}

# 运行主菜单
main_menu
