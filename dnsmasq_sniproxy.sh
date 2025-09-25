#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 请使用root用户来执行脚本!" && exit 1

disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}

check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /etc/issue; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /etc/issue; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        systemPackage="yum"
    elif grep -Eqi "debian|raspbian" /proc/version; then
        release="debian"
        systemPackage="apt"
    elif grep -Eqi "ubuntu" /proc/version; then
        release="ubuntu"
        systemPackage="apt"
    elif grep -Eqi "centos|red hat|redhat" /proc/version; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ "${checkType}" == "sysRelease" ]]; then
        if [ "${value}" == "${release}" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "${checkType}" == "packageManager" ]]; then
        if [ "${value}" == "${systemPackage}" ]; then
            return 0
        else
            return 1
        fi
    fi
}

getversion(){
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

centosversion(){
    if check_sys sysRelease centos; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

get_ip(){
    local IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
    echo ${IP}
}

check_ip(){
    local checkip=$1   
    local valid_check=$(echo $checkip|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')   
    if echo $checkip|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then   
        if [ ${valid_check:-no} == "yes" ]; then   
            return 0   
        else   
            echo -e "[${red}Error${plain}] IP $checkip not available!"   
            return 1   
        fi   
    else   
        echo -e "[${red}Error${plain}] IP format error!"   
        return 1   
    fi
}

download(){
    local filename=${1}
    echo -e "[${green}Info${plain}] ${filename} download configuration now..."
    wget --no-check-certificate -q -t3 -T60 -O ${1} ${2}
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Download ${filename} failed."
        exit 1
    fi
}

error_detect_depends(){
    local command=$1
    local depend=`echo "${command}" | awk '{print $4}'`
    echo -e "[${green}Info${plain}] Starting to install package ${depend}"
    ${command} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Failed to install ${red}${depend}${plain}"
        exit 1
    fi
}

config_firewall(){
    echo "配置防火墙规则..."
    if centosversion 6; then
        /etc/init.d/iptables status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            for port in ${ports}; do
                iptables -L -n | grep -i ${port} > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                    iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${port} -j ACCEPT
                    if [ ${port} == "53" ]; then
                        iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${port} -j ACCEPT
                        # 添加来源IP限制（可选）
                        # iptables -I INPUT -s 192.168.0.0/16 -p udp --dport 53 -j ACCEPT
                        # iptables -I INPUT -s 10.0.0.0/8 -p udp --dport 53 -j ACCEPT
                    fi
                else
                    echo -e "[${green}Info${plain}] port ${green}${port}${plain} already be enabled."
                fi
            done
            # 防止DNS放大攻击
            iptables -I INPUT -p udp --dport 53 -m string --algo bm --hex-string "|00000000000103697363036f726700|" -j DROP
            iptables -I INPUT -p udp --dport 53 -m state --state NEW -m recent --set --name DNS --rsource
            iptables -I INPUT -p udp --dport 53 -m state --state NEW -m recent --update --seconds 2 --hitcount 30 --name DNS --rsource -j DROP
            /etc/init.d/iptables save
            /etc/init.d/iptables restart
        else
            echo -e "[${yellow}Warning${plain}] iptables looks like not running or not installed, please enable port ${ports} manually if necessary."
        fi
    elif centosversion 7 || centosversion 8; then
        systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            default_zone=$(firewall-cmd --get-default-zone)
            for port in ${ports}; do
                firewall-cmd --permanent --zone=${default_zone} --add-port=${port}/tcp
                if [ ${port} == "53" ]; then
                    firewall-cmd --permanent --zone=${default_zone} --add-port=${port}/udp
                fi
            done
            # 添加DNS服务
            firewall-cmd --permanent --zone=${default_zone} --add-service=dns
            # 添加富规则以防止DNS放大攻击
            firewall-cmd --permanent --zone=${default_zone} --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" service name="dns" accept'
            firewall-cmd --permanent --zone=${default_zone} --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" service name="dns" accept'
            firewall-cmd --permanent --zone=${default_zone} --add-rich-rule='rule family="ipv4" source address="172.16.0.0/12" service name="dns" accept'
            firewall-cmd --reload
        else
            echo -e "[${yellow}Warning${plain}] firewalld looks like not running or not installed, please enable port ${ports} manually if necessary."
        fi
    fi
    echo -e "[${green}Info${plain}] 防火墙配置完成."
}

install_dependencies(){
    echo "安装依赖软件..."
    if check_sys packageManager yum; then
        echo -e "[${green}Info${plain}] Checking the EPEL repository..."
        if [ ! -f /etc/yum.repos.d/epel.repo ]; then
            yum install -y epel-release > /dev/null 2>&1
        fi
        [ ! -f /etc/yum.repos.d/epel.repo ] && echo -e "[${red}Error${plain}] Install EPEL repository failed, please check it." && exit 1
        [ ! "$(command -v yum-config-manager)" ] && yum install -y yum-utils > /dev/null 2>&1
        [ x"$(yum-config-manager epel | grep -w enabled | awk '{print $3}')" != x"True" ] && yum-config-manager --enable epel > /dev/null 2>&1
        echo -e "[${green}Info${plain}] Checking the EPEL repository complete..."

        if [[ ${fastmode} = "1" ]]; then
            yum_depends=(
                curl gettext-devel libev-devel pcre-devel perl udns-devel
            )
        else
            yum_depends=(
                git autoconf automake curl gettext-devel libev-devel pcre-devel perl pkgconfig rpm-build udns-devel
            )
        fi
        for depend in ${yum_depends[@]}; do
            error_detect_depends "yum -y install ${depend}"
        done
        if [[ ${fastmode} = "0" ]]; then
            if centosversion 6; then
                error_detect_depends "yum -y groupinstall development"
                error_detect_depends "yum -y install centos-release-scl"
                error_detect_depends "yum -y install devtoolset-6-gcc-c++"
            elif centosversion 7 || centosversion 8; then
                yum config-manager --set-enabled powertools
                yum groups list development | grep Installed > /dev/null 2>&1
                if [[ $? -eq 0 ]]; then
                    yum groups mark remove development -y > /dev/null 2>&1
                fi
                error_detect_depends "yum -y groupinstall development"
            fi
        fi
    elif check_sys packageManager apt; then
        if [[ ${fastmode} = "1" ]]; then
            apt_depends=(
                curl gettext libev-dev libpcre3-dev libudns-dev
            )
        else
            apt_depends=(
                git autotools-dev cdbs debhelper dh-autoreconf dpkg-dev gettext libev-dev libpcre3-dev libudns-dev pkg-config fakeroot devscripts
            )
        fi
        apt-get -y update
        for depend in ${apt_depends[@]}; do
            error_detect_depends "apt-get -y install ${depend}"
        done
        if [[ ${fastmode} = "0" ]]; then
            error_detect_depends "apt-get -y install build-essential"
        fi
    fi
}

compile_dnsmasq(){
    if check_sys packageManager yum; then
        error_detect_depends "yum -y install epel-release"
        error_detect_depends "yum -y install make"
        error_detect_depends "yum -y install gcc-c++"
        error_detect_depends "yum -y install nettle-devel"
        error_detect_depends "yum -y install gettext"
        error_detect_depends "yum -y install libidn-devel"
        #error_detect_depends "yum -y install libidn2-devel"
        error_detect_depends "yum -y install libnetfilter_conntrack-devel"
        error_detect_depends "yum -y install dbus-devel"
    elif check_sys packageManager apt; then
        error_detect_depends "apt -y install make"
        error_detect_depends "apt -y install gcc"
        error_detect_depends "apt -y install g++"
        error_detect_depends "apt -y install pkg-config"
        error_detect_depends "apt -y install nettle-dev"
        error_detect_depends "apt -y install gettext"
        error_detect_depends "apt -y install libidn11-dev"
        #error_detect_depends "apt -y install libidn2-dev"
        error_detect_depends "apt -y install libnetfilter-conntrack-dev"
        error_detect_depends "apt -y install libdbus-1-dev"
    fi
    if [ -e /tmp/dnsmasq-2.90 ]; then
        rm -rf /tmp/dnsmasq-2.90
    fi
    cd /tmp/
    download dnsmasq-2.90.tar.gz https://thekelleys.org.uk/dnsmasq/dnsmasq-2.90.tar.gz
    tar -zxf dnsmasq-2.90.tar.gz
    cd dnsmasq-2.90
    make all-i18n V=s COPTS='-DHAVE_DNSSEC -DHAVE_IDN -DHAVE_CONNTRACK -DHAVE_DBUS'
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] dnsmasq upgrade failed."
        rm -rf /tmp/dnsmasq-2.90 /tmp/dnsmasq-2.90.tar.gz
        exit 1
    fi
}

install_dnsmasq(){
    netstat -a -n -p | grep LISTEN | grep -P "\d+\.\d+\.\d+\.\d+:53\s+" > /dev/null && echo -e "[${red}Error${plain}] required port 53 already in use\n" && exit 1
    echo "安装Dnsmasq..."
    if check_sys packageManager yum; then
        error_detect_depends "yum -y install dnsmasq"
        if centosversion 6; then
            compile_dnsmasq
            yes|cp -f /tmp/dnsmasq-2.90/src/dnsmasq /usr/sbin/dnsmasq && chmod +x /usr/sbin/dnsmasq
        fi
    elif check_sys packageManager apt; then
        error_detect_depends "apt -y install dnsmasq"
    fi
    if [[ ${fastmode} = "0" ]]; then
        compile_dnsmasq
        yes|cp -f /tmp/dnsmasq-2.90/src/dnsmasq /usr/sbin/dnsmasq && chmod +x /usr/sbin/dnsmasq
    fi
    [ ! -f /usr/sbin/dnsmasq ] && echo -e "[${red}Error${plain}] 安装dnsmasq出现问题，请检查." && exit 1

    # 创建基础配置文件
    cat > /etc/dnsmasq.d/base.conf << EOF
# 监听所有网络接口
interface=*
listen-address=0.0.0.0

# 绑定接口，防止DNS放大攻击
bind-interfaces

# DNS缓存大小设置
cache-size=10000

# 设置最小TTL值
min-cache-ttl=300

# 不转发不合法域名
domain-needed
bogus-priv

# 上游DNS服务器配置
server=8.8.8.8
server=8.8.4.4
server=1.1.1.1
server=223.5.5.5
server=119.29.29.29

# 严格按照resolv.conf中的顺序进行查询
strict-order

# 并发查询所有上游DNS服务器
all-servers

# 不读取/etc/resolv.conf
no-resolv

# 扩展主机文件
expand-hosts

# 日志设置
log-queries
log-facility=/var/log/dnsmasq.log

# DNS查询超时设置
dns-forward-max=5000

# 启用DNSSEC验证
#dnssec
#trust-anchor=.,19036,8,2,49AAC11D7B6F6446702E54A1607371607A1A41855200FD2CE1CDDE32F24E8FB5
#dnssec-check-unsigned
EOF

    download /etc/dnsmasq.d/custom_netflix.conf https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/dnsmasq.conf
    download /tmp/proxy-domains.txt https://raw.githubusercontent.com/ridaiqianhe/dnsmasq/master/proxy-domains.txt
    for domain in $(cat /tmp/proxy-domains.txt); do
        printf "address=/${domain}/${publicip}\n"\
        | tee -a /etc/dnsmasq.d/custom_netflix.conf > /dev/null 2>&1
    done

    # 添加自定义配置
    cat > /etc/dnsmasq.d/custom.conf << EOF
# 自定义域名解析
# address=/example.com/192.168.1.100

# 屏蔽广告域名示例
# address=/doubleclick.net/0.0.0.0
# address=/googleadservices.com/0.0.0.0

# PTR记录自动生成
# ptr-record=1.1.168.192.in-addr.arpa,router.local
EOF

    [ "$(grep -x -E "(conf-dir=/etc/dnsmasq.d|conf-dir=/etc/dnsmasq.d,.bak|conf-dir=/etc/dnsmasq.d/,\*.conf|conf-dir=/etc/dnsmasq.d,.rpmnew,.rpmsave,.rpmorig)" /etc/dnsmasq.conf)" ] || echo -e "\nconf-dir=/etc/dnsmasq.d" >> /etc/dnsmasq.conf

    # 创建日志目录
    mkdir -p /var/log
    touch /var/log/dnsmasq.log
    chmod 644 /var/log/dnsmasq.log
    echo "启动 Dnsmasq 服务..."
    if check_sys packageManager yum; then
        if centosversion 6; then
            chkconfig dnsmasq on
            service dnsmasq start
        elif centosversion 7 || centosversion 8; then
            systemctl enable dnsmasq
            systemctl start dnsmasq
        fi
    elif check_sys packageManager apt; then
        systemctl enable dnsmasq
        systemctl restart dnsmasq
    fi
    cd /tmp
    rm -rf /tmp/dnsmasq-2.90 /tmp/dnsmasq-2.90.tar.gz /tmp/proxy-domains.txt
    echo -e "[${green}Info${plain}] dnsmasq install complete..."
}

install_sniproxy(){
    for aport in 80 443; do
        netstat -a -n -p | grep LISTEN | grep -P "\d+\.\d+\.\d+\.\d+:${aport}\s+" > /dev/null && echo -e "[${red}Error${plain}] required port ${aport} already in use\n" && exit 1
    done
    install_dependencies
    echo "安装SNI Proxy..."
    if check_sys packageManager yum; then
        rpm -qa | grep sniproxy >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            rpm -e sniproxy
        fi
    elif check_sys packageManager apt; then
        dpkg -s sniproxy >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            dpkg -r sniproxy
        fi
    fi
    bit=`uname -m`
    cd /tmp
    if [[ ${fastmode} = "0" ]]; then
        if [ -e sniproxy ]; then
            rm -rf sniproxy
        fi
        git clone https://github.com/dlundquist/sniproxy.git
        cd sniproxy
    fi
    if check_sys packageManager yum; then
        if [[ ${fastmode} = "1" ]]; then
            if [[ ${bit} = "x86_64" ]]; then
                download /tmp/sniproxy-0.6.1-1.el8.x86_64.rpm https://github.com/myxuchangbin/dnsmasq_sniproxy_install/raw/master/sniproxy/sniproxy-0.6.1-1.el8.x86_64.rpm
                error_detect_depends "yum -y install /tmp/sniproxy-0.6.1-1.el8.x86_64.rpm"
                rm -rf /tmp/sniproxy-0.6.1-1.el8.x86_64.rpm
            else
                echo -e "${red}暂不支持${bit}内核，请使用编译模式安装！${plain}" && exit 1
            fi
        else
            ./autogen.sh && ./configure && make dist
            if centosversion 6; then
                scl enable devtoolset-6 'rpmbuild --define "_sourcedir `pwd`" --define "_topdir /tmp/sniproxy/rpmbuild" --define "debug_package %{nil}" -ba redhat/sniproxy.spec'
                download /etc/init.d/sniproxy https://raw.githubusercontent.com/dlundquist/sniproxy/master/redhat/sniproxy.init && chmod +x /etc/init.d/sniproxy
            elif centosversion 7 || centosversion 8; then
                sed -i "s/\%configure CFLAGS\=\"-I\/usr\/include\/libev\"/\%configure CFLAGS\=\"-fPIC -I\/usr\/include\/libev\"/" redhat/sniproxy.spec
                rpmbuild --define "_sourcedir `pwd`" --define "_topdir /tmp/sniproxy/rpmbuild" --define "debug_package %{nil}" -ba redhat/sniproxy.spec
            fi
            error_detect_depends "yum -y install /tmp/sniproxy/rpmbuild/RPMS/x86_64/sniproxy-*.rpm"
        fi
        if centosversion 6; then
            download /etc/init.d/sniproxy https://raw.githubusercontent.com/dlundquist/sniproxy/master/redhat/sniproxy.init && chmod +x /etc/init.d/sniproxy
            [ ! -f /etc/init.d/sniproxy ] && echo -e "[${red}Error${plain}] 下载Sniproxy启动文件出现问题，请检查." && exit 1
        elif centosversion 7 || centosversion 8; then
            download /etc/systemd/system/sniproxy.service https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/sniproxy.service
            systemctl daemon-reload
            [ ! -f /etc/systemd/system/sniproxy.service ] && echo -e "[${red}Error${plain}] 下载Sniproxy启动文件出现问题，请检查." && exit 1
        fi
    elif check_sys packageManager apt; then
        if [[ ${fastmode} = "1" ]]; then
            if [[ ${bit} = "x86_64" ]]; then
                download /tmp/sniproxy_0.6.1_amd64.deb https://github.com/myxuchangbin/dnsmasq_sniproxy_install/raw/master/sniproxy/sniproxy_0.6.1_amd64.deb
                error_detect_depends "dpkg -i --no-debsig /tmp/sniproxy_0.6.1_amd64.deb"
                rm -rf /tmp/sniproxy_0.6.1_amd64.deb
            else
                echo -e "${red}暂不支持${bit}内核，请使用编译模式安装！${plain}" && exit 1
            fi
        else
            ./autogen.sh && dpkg-buildpackage
            error_detect_depends "dpkg -i --no-debsig ../sniproxy_*.deb"
            rm -rf /tmp/sniproxy*.deb
        fi  
        download /etc/systemd/system/sniproxy.service https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/sniproxy.service
        systemctl daemon-reload
        [ ! -f /etc/systemd/system/sniproxy.service ] && echo -e "[${red}Error${plain}] 下载Sniproxy启动文件出现问题，请检查." && exit 1
    fi
    [ ! -f /usr/sbin/sniproxy ] && echo -e "[${red}Error${plain}] 安装Sniproxy出现问题，请检查." && exit 1
    download /etc/sniproxy.conf https://raw.githubusercontent.com/myxuchangbin/dnsmasq_sniproxy_install/master/sniproxy.conf
    download /tmp/sniproxy-domains.txt https://raw.githubusercontent.com/ridaiqianhe/dnsmasq/master/proxy-domains.txt
    sed -i -e 's/\./\\\./g' -e 's/^/    \.\*/' -e 's/$/\$ \*/' /tmp/sniproxy-domains.txt || (echo -e "[${red}Error:${plain}] Failed to configuration sniproxy." && exit 1)
    sed -i '/table {/r /tmp/sniproxy-domains.txt' /etc/sniproxy.conf || (echo -e "[${red}Error:${plain}] Failed to configuration sniproxy." && exit 1)
    if [ ! -e /var/log/sniproxy ]; then
        mkdir /var/log/sniproxy
    fi
    echo "启动 SNI Proxy 服务..."
    if check_sys packageManager yum; then
        if centosversion 6; then
            chkconfig sniproxy on > /dev/null 2>&1
            service sniproxy start || (echo -e "[${red}Error:${plain}] Failed to start sniproxy." && exit 1)
        elif centosversion 7 || centosversion 8; then
            systemctl enable sniproxy > /dev/null 2>&1
            systemctl start sniproxy || (echo -e "[${red}Error:${plain}] Failed to start sniproxy." && exit 1)
        fi
    elif check_sys packageManager apt; then
        systemctl enable sniproxy > /dev/null 2>&1
        systemctl restart sniproxy || (echo -e "[${red}Error:${plain}] Failed to start sniproxy." && exit 1)
    fi
    cd /tmp
    rm -rf /tmp/sniproxy/
    rm -rf /tmp/sniproxy-domains.txt
    echo -e "[${green}Info${plain}] sniproxy install complete..."
}

install_check(){
    if check_sys packageManager yum || check_sys packageManager apt; then
        if centosversion 5; then
            return 1
        fi
        return 0
    else
        return 1
    fi
}

ready_install(){
    echo "检测您的系统..."
    if ! install_check; then
        echo -e "[${red}Error${plain}] Your OS is not supported to run it!"
        echo -e "Please change to CentOS 6+/Debian 8+/Ubuntu 16+ and try again."
        exit 1
    fi
    if check_sys packageManager yum; then
        yum makecache
        error_detect_depends "yum -y install net-tools"
        error_detect_depends "yum -y install wget"
    elif check_sys packageManager apt; then
        apt update
        error_detect_depends "apt-get -y install net-tools"
        error_detect_depends "apt-get -y install wget"
    fi
    disable_selinux
    if check_sys packageManager yum; then
        config_firewall
    fi
    echo -e "[${green}Info${plain}] Checking the system complete..."
}

hello(){
    echo ""
    echo -e "${yellow}Dnsmasq + SNI Proxy自助安装脚本${plain}"
    echo -e "${yellow}支持系统:  CentOS 6+, Debian8+, Ubuntu16+${plain}"
    echo -e "${green}增强版: 支持作为DNS服务器供其他机器使用${plain}"
    echo ""
}

help(){
    hello
    echo "使用方法：bash $0 [-h] [-i] [-f] [-id] [-fd] [-is] [-fs] [-u] [-ud] [-us] [-c] [-s]"
    echo ""
    echo "  -h , --help                显示帮助信息"
    echo "  -i , --install             安装 Dnsmasq + SNI Proxy"
    echo "  -f , --fastinstall         快速安装 Dnsmasq + SNI Proxy"
    echo "  -id, --installdnsmasq      仅安装 Dnsmasq"
    echo "  -fd, --fastinstalldnsmasq  快速安装 Dnsmasq"
    echo "  -is, --installsniproxy     仅安装 SNI Proxy"
    echo "  -fs, --fastinstallsniproxy 快速安装 SNI Proxy"
    echo "  -u , --uninstall           卸载 Dnsmasq + SNI Proxy"
    echo "  -ud, --undnsmasq           卸载 Dnsmasq"
    echo "  -us, --unsniproxy          卸载 SNI Proxy"
    echo "  -c , --check               检查服务状态"
    echo "  -s , --status              显示DNS统计信息"
    echo ""
    echo "配置其他机器使用此DNS服务器:"
    echo "  1. 确保防火墙允许UDP 53端口"
    echo "  2. 在客户端机器配置DNS为本机IP: $(get_ip)"
    echo "  3. Windows: 网络设置 -> IPv4 -> DNS服务器"
    echo "  4. Linux: 编辑 /etc/resolv.conf 添加 nameserver $(get_ip)"
    echo "  5. macOS: 系统偏好设置 -> 网络 -> 高级 -> DNS"
    echo ""
}

install_all(){
    ports="53 80 443"
    publicip=$(get_ip)
    hello
    ready_install
    install_dnsmasq
    install_sniproxy
    echo ""
    echo -e "${yellow}Dnsmasq + SNI Proxy 已完成安装！${plain}"
    echo ""
    echo -e "${green}==================== DNS服务器配置信息 ====================${plain}"
    echo -e "${yellow}DNS服务器IP: ${green}$(get_ip)${plain}"
    echo -e "${yellow}监听端口: ${green}53 (UDP/TCP)${plain}"
    echo -e "${yellow}上游DNS: ${green}8.8.8.8, 1.1.1.1, 223.5.5.5${plain}"
    echo -e "${yellow}缓存大小: ${green}10000 条记录${plain}"
    echo -e "${yellow}日志文件: ${green}/var/log/dnsmasq.log${plain}"
    echo -e "${green}==========================================================${plain}"
    echo ""
    echo -e "${yellow}其他机器配置方法:${plain}"
    echo -e "  1. ${green}Linux系统:${plain} echo 'nameserver $(get_ip)' >> /etc/resolv.conf"
    echo -e "  2. ${green}Windows系统:${plain} 网络设置中将DNS服务器设置为 $(get_ip)"
    echo -e "  3. ${green}路由器:${plain} 在DHCP设置中将DNS服务器设置为 $(get_ip)"
    echo ""
    echo -e "${yellow}测试命令:${plain}"
    echo -e "  nslookup google.com $(get_ip)"
    echo -e "  dig @$(get_ip) google.com"
    echo ""
}

only_dnsmasq(){
    ports="53"
    hello
    ready_install
    inputipcount=1
    echo -e "请输入SNIProxy服务器的IP地址"
    read -e -p "(为空则自动获取公网IP): " inputip
    while true; do
        if [ "${inputipcount}" == 3 ]; then
            echo -e "[${red}Error:${plain}] IP输入错误次数过多，请重新执行脚本。"
            exit 1
        fi
        if [ -z ${inputip} ]; then
            publicip=$(get_ip)
            break
        else
            check_ip ${inputip}
            if [ $? -eq 0 ]; then
                publicip=${inputip}
                break
            else
                echo -e "请重新输入SNIProxy服务器的IP地址"
                read -e -p "(为空则自动获取公网IP): " inputip
            fi
        fi
        inputipcount=`expr ${inputipcount} + 1`
    done
    install_dnsmasq
    echo ""
    echo -e "${yellow}Dnsmasq 已完成安装！${plain}"
    echo ""
    echo -e "${green}==================== DNS服务器配置信息 ====================${plain}"
    echo -e "${yellow}DNS服务器IP: ${green}$(get_ip)${plain}"
    echo -e "${yellow}监听端口: ${green}53 (UDP/TCP)${plain}"
    echo -e "${yellow}配置文件: ${green}/etc/dnsmasq.conf, /etc/dnsmasq.d/*.conf${plain}"
    echo -e "${green}==========================================================${plain}"
    echo ""
    echo -e "${yellow}配置其他机器使用此DNS:${plain}"
    echo -e "  ${green}临时生效:${plain} echo 'nameserver $(get_ip)' > /etc/resolv.conf"
    echo -e "  ${green}永久生效:${plain} 编辑网络配置文件设置DNS为 $(get_ip)"
    echo ""
}

only_sniproxy(){
    ports="80 443"
    hello
    ready_install
    install_sniproxy
    echo ""
    echo -e "${yellow}SNI Proxy 已完成安装！${plain}"
    echo ""
    echo -e "${yellow}将Netflix的相关域名解析到 $(get_ip) 即可以观看Netflix节目了。${plain}"
    echo ""
}

undnsmasq(){
    echo -e "[${green}Info${plain}] Stoping dnsmasq services."
    if check_sys packageManager yum; then
        if centosversion 6; then
            chkconfig dnsmasq off > /dev/null 2>&1
            service dnsmasq stop || echo -e "[${red}Error:${plain}] Failed to stop dnsmasq."
        elif centosversion 7 || centosversion 8; then
            systemctl disable dnsmasq > /dev/null 2>&1
            systemctl stop dnsmasq || echo -e "[${red}Error:${plain}] Failed to stop dnsmasq."
        fi
    elif check_sys packageManager apt; then
        systemctl disable dnsmasq > /dev/null 2>&1
        systemctl stop dnsmasq || echo -e "[${red}Error:${plain}] Failed to stop dnsmasq."
    fi
    echo -e "[${green}Info${plain}] Starting to uninstall dnsmasq services."
    if check_sys packageManager yum; then
        yum remove dnsmasq -y > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] Failed to uninstall ${red}dnsmasq${plain}"
        fi
    elif check_sys packageManager apt; then
        apt-get remove dnsmasq -y > /dev/null 2>&1
        apt-get remove dnsmasq-base -y > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] Failed to uninstall ${red}dnsmasq${plain}"
        fi
    fi
    rm -rf /etc/dnsmasq.d/custom_netflix.conf
    echo -e "[${green}Info${plain}] services uninstall dnsmasq complete..."
}

unsniproxy(){
    echo -e "[${green}Info${plain}] Stoping sniproxy services."
    if check_sys packageManager yum; then
        if centosversion 6; then
            chkconfig sniproxy off > /dev/null 2>&1
            service sniproxy stop || echo -e "[${red}Error:${plain}] Failed to stop sniproxy."
        elif centosversion 7 || centosversion 8; then
            systemctl disable sniproxy > /dev/null 2>&1
            systemctl stop sniproxy || echo -e "[${red}Error:${plain}] Failed to stop sniproxy."
        fi
    elif check_sys packageManager apt; then
        systemctl disable sniproxy > /dev/null 2>&1
        systemctl stop sniproxy || echo -e "[${red}Error:${plain}] Failed to stop sniproxy."
    fi
    echo -e "[${green}Info${plain}] Starting to uninstall sniproxy services."
    if check_sys packageManager yum; then
        yum remove sniproxy -y > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] Failed to uninstall ${red}sniproxy${plain}"
        fi
    elif check_sys packageManager apt; then
        apt-get remove sniproxy -y > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] Failed to uninstall ${red}sniproxy${plain}"
        fi
    fi
    rm -rf /etc/sniproxy.conf
    echo -e "[${green}Info${plain}] services uninstall sniproxy complete..."
}

check_services(){
    hello
    echo -e "${yellow}检查服务状态...${plain}"
    echo ""

    # 检查 Dnsmasq 状态
    echo -e "${green}========== Dnsmasq 服务状态 ==========${plain}"
    if [ -f /usr/sbin/dnsmasq ]; then
        if check_sys packageManager yum; then
            if centosversion 6; then
                service dnsmasq status
            else
                systemctl status dnsmasq --no-pager
            fi
        elif check_sys packageManager apt; then
            systemctl status dnsmasq --no-pager
        fi

        # 检查端口监听
        echo ""
        echo -e "${yellow}DNS 端口监听状态:${plain}"
        netstat -tunlp | grep :53
    else
        echo -e "${red}Dnsmasq 未安装${plain}"
    fi

    echo ""
    echo -e "${green}========== SNI Proxy 服务状态 ==========${plain}"
    if [ -f /usr/sbin/sniproxy ]; then
        if check_sys packageManager yum; then
            if centosversion 6; then
                service sniproxy status
            else
                systemctl status sniproxy --no-pager
            fi
        elif check_sys packageManager apt; then
            systemctl status sniproxy --no-pager
        fi

        # 检查端口监听
        echo ""
        echo -e "${yellow}HTTP/HTTPS 端口监听状态:${plain}"
        netstat -tunlp | grep -E ':80|:443'
    else
        echo -e "${red}SNI Proxy 未安装${plain}"
    fi

    echo ""
    echo -e "${green}========== 系统信息 ==========${plain}"
    echo -e "${yellow}系统IP地址:${plain} $(get_ip)"
    echo -e "${yellow}系统版本:${plain} $(cat /etc/*release | head -n 1)"
    echo -e "${yellow}内核版本:${plain} $(uname -r)"
    echo ""
}

show_dns_stats(){
    hello
    echo -e "${yellow}DNS 统计信息...${plain}"
    echo ""

    if [ ! -f /usr/sbin/dnsmasq ]; then
        echo -e "${red}Dnsmasq 未安装${plain}"
        return 1
    fi

    # 发送 USR1 信号让 dnsmasq 输出统计信息
    if check_sys packageManager yum; then
        if centosversion 6; then
            killall -USR1 dnsmasq 2>/dev/null
        else
            systemctl kill -s USR1 dnsmasq 2>/dev/null
        fi
    elif check_sys packageManager apt; then
        systemctl kill -s USR1 dnsmasq 2>/dev/null
    fi

    sleep 1

    echo -e "${green}========== DNS 查询统计 ==========${plain}"
    if [ -f /var/log/dnsmasq.log ]; then
        echo -e "${yellow}最近的DNS查询记录:${plain}"
        tail -n 20 /var/log/dnsmasq.log
        echo ""
        echo -e "${yellow}今日查询统计:${plain}"
        today=$(date +%b\ %d)
        echo "总查询数: $(grep "$today" /var/log/dnsmasq.log 2>/dev/null | wc -l)"
        echo "缓存命中: $(grep "$today.*cached" /var/log/dnsmasq.log 2>/dev/null | wc -l)"
        echo "转发查询: $(grep "$today.*forwarded" /var/log/dnsmasq.log 2>/dev/null | wc -l)"
        echo ""
        echo -e "${yellow}热门查询域名 (Top 10):${plain}"
        grep "$today.*query" /var/log/dnsmasq.log 2>/dev/null | awk '{print $6}' | sort | uniq -c | sort -rn | head -10
    else
        echo -e "${yellow}日志文件不存在，请检查dnsmasq配置${plain}"
    fi

    echo ""
    echo -e "${green}========== 系统资源使用 ==========${plain}"
    ps aux | grep -E "dnsmasq|sniproxy" | grep -v grep
    echo ""
}

confirm(){
    echo -e "${yellow}是否继续执行?(n:取消/y:继续)${plain}"
    read -e -p "(默认:取消): " selection
    [ -z "${selection}" ] && selection="n"
    if [ ${selection} != "y" ]; then
        exit 0
    fi
}

if [[ $# = 1 ]];then
    key="$1"
    case $key in
        -i|--install)
        fastmode=0
        install_all
        ;;
        -f|--fastinstall)
        fastmode=1
        install_all
        ;;
        -id|--installdnsmasq)
        fastmode=0
        only_dnsmasq
        ;;
        -fd|--fastinstalldnsmasq)
        fastmode=1
        only_dnsmasq
        ;;
        -is|--installsniproxy)
        fastmode=0
        only_sniproxy
        ;;
        -fs|--fastinstallsniproxy)
        fastmode=1
        only_sniproxy
        ;;
        -u|--uninstall)
        hello
        echo -e "${yellow}正在执行卸载Dnsmasq和SNI Proxy.${plain}"
        confirm
        undnsmasq
        unsniproxy
        ;;
        -ud|--undnsmasq)
        hello
        echo -e "${yellow}正在执行卸载Dnsmasq.${plain}"
        confirm
        undnsmasq
        ;;
        -us|--unsniproxy)
        hello
        echo -e "${yellow}正在执行卸载SNI Proxy.${plain}"
        confirm
        unsniproxy
        ;;
        -c|--check)
        check_services
        ;;
        -s|--status)
        show_dns_stats
        ;;
        -h|--help|*)
        help
        ;;
    esac
else
    help
fi
