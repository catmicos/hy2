#!/bin/bash

# 定义带延迟的打印函数
print_with_delay() {
    local message="$1"
    local delay="$2"
    for (( i=0; i<${#message}; i++ )); do
        echo -n "${message:$i:1}"
        sleep "$delay"
    done
    echo
}

# 自动安装 Hysteria 2
print_with_delay "正在安装 Hysteria 2..." 0.03
bash <(curl -fsSL https://get.hy2.sh/)

# 生成自签名证书
print_with_delay "生成自签名证书..." 0.03
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=bing.com" -days 36500 && \
    sudo chown hysteria /etc/hysteria/server.key && \
    sudo chown hysteria /etc/hysteria/server.crt

# 自动生成密码
AUTH_PASSWORD=$(openssl rand -base64 16)
OBFS_PASSWORD=$(openssl rand -base64 16)

# 提示输入监听端口号
read -p "请输入监听端口: " PORT

# 获取设备的所有 IPv4 和 IPv6 地址并显示
print_with_delay "正在获取设备的内网 IP 地址..." 0.03
IP_LIST=$(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1)
IP_LIST_IPV6=$(ip -o -6 addr show | awk '{print $4}' | cut -d/ -f1)

# 获取公网 IP 地址
print_with_delay "正在获取公网 IP 地址..." 0.03
PUBLIC_IP=$(curl -s https://ipinfo.io/ip)

# 列出内网和公网 IP 地址供用户选择
print_with_delay "请选择你想使用的服务器 IP 地址:" 0.03
i=1
for ip in $IP_LIST; do
    print_with_delay "$i. 内网 IPv4 地址: $ip" 0.03
    ((i++))
done

for ip6 in $IP_LIST_IPV6; do
    print_with_delay "$i. 内网 IPv6 地址: $ip6" 0.03
    ((i++))
done

print_with_delay "$i. 公网 IP 地址: $PUBLIC_IP" 0.03
((i++))

read -p "请输入对应的数字选择: " IP_CHOICE

# 根据用户的选择设置服务器 IP 地址
SELECTED_IP=""
i=1
for ip in $IP_LIST; do
    if [ "$IP_CHOICE" == "$i" ]; then
        SELECTED_IP=$ip
        break
    fi
    ((i++))
done

for ip6 in $IP_LIST_IPV6; do
    if [ "$IP_CHOICE" == "$i" ]; then
        SELECTED_IP=$ip6
        break
    fi
    ((i++))
done

if [ "$IP_CHOICE" == "$i" ]; then
    SELECTED_IP=$PUBLIC_IP
fi

# 如果未选择 IP 地址则退出
if [ -z "$SELECTED_IP" ]; then
    print_with_delay "无效选择，退出脚本。" 0.03
    exit 1
fi

# 创建 Hysteria 2 服务端配置文件
print_with_delay "生成 Hysteria 2 配置文件..." 0.03
cat << EOF > /etc/hysteria/config.yaml
listen: ":$PORT"  # 这里使用省略地址的格式，只监听端口

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $AUTH_PASSWORD
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true

obfs:
  type: salamander
  salamander:
    password: $OBFS_PASSWORD
EOF

# 启动并启用 Hysteria 服务
print_with_delay "启动 Hysteria 服务..." 0.03
systemctl start hysteria-server.service
systemctl enable hysteria-server.service

# 创建客户端配置文件目录
mkdir -p /root/hy2

# 生成客户端配置文件，使用用户选择的 IP 地址和服务端端口
print_with_delay "生成客户端配置文件..." 0.03
cat << EOF > /root/hy2/config.yaml
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
ipv6: true

dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:        
  - name: Hysteria2
    server: $SELECTED_IP
    port: $PORT
    type: hysteria2
    up: "40 Mbps"
    down: "120 Mbps"
    udp: true
    sni: bing.com
    obfs: salamander
    password: $AUTH_PASSWORD
    skip-cert-verify: true
    obfs-password: $OBFS_PASSWORD
    alpn:
      - h3

proxy-groups:
  - name: 节点选择
    type: select
    proxies:
      - 自动选择
      - Hysteria2
      - DIRECT

  - name: 自动选择
    type: url-test
    proxies:
      - Hysteria2
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50

rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
EOF

# 显示生成的密码
print_with_delay "Hysteria 2 安装和配置完成！" 0.03
print_with_delay "认证密码: $AUTH_PASSWORD" 0.03
print_with_delay "混淆密码: $OBFS_PASSWORD" 0.03
print_with_delay "服务端配置文件已保存到 /etc/hysteria/config.yaml" 0.03
print_with_delay "客户端配置文件已保存到 /root/hy2/config.yaml" 0.03

# 重启 Hysteria 服务以应用配置
print_with_delay "重启 Hysteria 服务以应用新配置..." 0.03
systemctl restart hysteria-server.service

# 显示 Hysteria 服务状态
print_with_delay "显示 Hysteria 服务状态..." 0.03
systemctl status hysteria-server.service --no-pager

# 显示客户端配置文件的内容
print_with_delay "客户端配置文件内容如下:" 0.03
cat /root/hy2/config.yaml
