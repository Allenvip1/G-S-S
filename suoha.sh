#!/bin/bash
# onekey suoha
linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0
for i in `echo ${linux_os[@]}`
do
    if [ $i == $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') ]
    then
        break
    else
        n=$[$n+1]
    fi
done
if [ $n == 5 ]
then
    echo 当前系统$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2)没有适配
    echo 默认使用APT包管理器
    n=0
fi
if [ -z $(type -P unzip) ]
then
    ${linux_update[$n]}
    ${linux_install[$n]} unzip
fi
if [ -z $(type -P curl) ]
then
    ${linux_update[$n]}
    ${linux_install[$n]} curl
fi
if [ -z $(type -P python3) ]
then
    ${linux_update[$n]}
    ${linux_install[$n]} python3
fi
if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') != "Alpine" ]
then
    if [ -z $(type -P systemctl) ]
    then
        ${linux_update[$n]}
        ${linux_install[$n]} systemctl
    fi
fi

function get_server_ip(){
    local ip=""
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [[ -z "$ip" || "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
        ip=$(curl -s4 --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/ip/{print $2}')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s4 --connect-timeout 2 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\n\r ')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s4 --connect-timeout 2 https://api.ip.sb/ip 2>/dev/null | tr -d '\n\r ')
    fi
    if [ -z "$ip" ]; then
        ip=$(curl -s6 --connect-timeout 2 https://api64.ipify.org 2>/dev/null | tr -d '\n\r ')
    fi
    echo "$ip"
}

function start_sub_server(){
    local web_dir="$1"
    local port="$2"

    pkill -f "http.server $port" >/dev/null 2>&1
    fuser -k ${port}/tcp >/dev/null 2>&1

    if [ -x "$(command -v python3)" ]; then
        nohup python3 -m http.server $port --directory "$web_dir" >/dev/null 2>&1 &
    elif [ -x "$(command -v python)" ]; then
        cd "$web_dir" && nohup python -m SimpleHTTPServer $port >/dev/null 2>&1 &
        cd - >/dev/null 2>&1
    fi
}

function quicktunnel(){
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
    x86_64 | x64 | amd64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
    ;;
    i386 | i686 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
    ;;
    armv8 | arm64 | aarch64 )
    echo arm64
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
    ;;
    armv7l )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
    ;;
    * )
    echo 当前架构$(uname -m)没有适配
    exit
    ;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
rm -rf xray.zip
uuid=$(cat /proc/sys/kernel/random/uuid)
urlpath_vless="vl-$(echo $uuid | awk -F- '{print $1}')"
urlpath_trojan="tr-$(echo $uuid | awk -F- '{print $1}')"
port_vless=$[$RANDOM+10000]
port_trojan=$[$port_vless+1]

# 同时创建 VLESS 与 Trojan 双 inbound
cat>xray/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port_vless,
            "listen": "localhost",
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/$urlpath_vless"
                }
            }
        },
        {
            "port": $port_trojan,
            "listen": "localhost",
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/$urlpath_trojan"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF

./xray/xray run>/dev/null 2>&1 &

# cloudflared 路径分流规则
cat>quick_tunnel.yaml<<EOF
ingress:
  - path: /$urlpath_vless
    service: http://localhost:$port_vless
  - path: /$urlpath_trojan
    service: http://localhost:$port_trojan
  - service: http_status:404
EOF

./cloudflared-linux tunnel --config quick_tunnel.yaml --no-autoupdate --edge-ip-version $ips --protocol http2 run >argo.log 2>&1 &
sleep 1
n=0
while true
do
n=$[$n+1]
clear
echo 等待cloudflare argo生成地址 已等待 $n 秒
argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [ -z "$argo" ]; then
    argo=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" argo.log | head -n 1 | awk -F// '{print $2}')
fi

if [ $n == 15 ]
then
    n=0
    if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
    then
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    rm -rf argo.log
    clear
    echo argo获取超时,重试中
    ./cloudflared-linux tunnel --config quick_tunnel.yaml --no-autoupdate --edge-ip-version $ips --protocol http2 run >argo.log 2>&1 &
    sleep 1
elif [ -z "$argo" ]
then
    sleep 1
else
    rm -rf argo.log
    break
fi
done
clear

node_tag=$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')
if [[ -z "$node_tag" || "$node_tag" == "--" ]]; then
    node_tag="Argo_Node"
fi

domains=("$argo" "cf.090227.xyz" "cloudflare.182682.xyz")
labels=("默认Argo" "优选cf.090227" "优选182682")

> nodes.txt

cat>clash.yaml<<EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
proxies:
EOF

proxy_names=()

for idx in "${!domains[@]}"; do
    d="${domains[$idx]}"
    l="${labels[$idx]}"

    # VLESS TLS 节点
    vless_tls="vless://${uuid}@${d}:443?encryption=none&security=tls&sni=${argo}&type=ws&host=${argo}&path=%2F${urlpath_vless}#${node_tag}-VLESS-${l}-443"
    echo "$vless_tls" >> nodes.txt
    proxy_names+=("${node_tag}-VLESS-${l}-443")
    cat>>clash.yaml<<EOF
  - name: "${node_tag}-VLESS-${l}-443"
    type: vless
    server: ${d}
    port: 443
    uuid: ${uuid}
    cipher: auto
    tls: true
    udp: true
    servername: ${argo}
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${argo}
EOF

    # VLESS 80 节点
    vless_80="vless://${uuid}@${d}:80?encryption=none&security=none&type=ws&host=${argo}&path=%2F${urlpath_vless}#${node_tag}-VLESS-${l}-80"
    echo "$vless_80" >> nodes.txt
    proxy_names+=("${node_tag}-VLESS-${l}-80")
    cat>>clash.yaml<<EOF
  - name: "${node_tag}-VLESS-${l}-80"
    type: vless
    server: ${d}
    port: 80
    uuid: ${uuid}
    cipher: auto
    tls: false
    udp: true
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${argo}
EOF

    # Trojan TLS 节点
    trojan_tls="trojan://${uuid}@${d}:443?security=tls&sni=${argo}&type=ws&host=${argo}&path=%2F${urlpath_trojan}#${node_tag}-Trojan-${l}-443"
    echo "$trojan_tls" >> nodes.txt
    proxy_names+=("${node_tag}-Trojan-${l}-443")
    cat>>clash.yaml<<EOF
  - name: "${node_tag}-Trojan-${l}-443"
    type: trojan
    server: ${d}
    port: 443
    password: ${uuid}
    udp: true
    sni: ${argo}
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${argo}
EOF

    # Trojan 80 节点
    trojan_80="trojan://${uuid}@${d}:80?security=none&type=ws&host=${argo}&path=%2F${urlpath_trojan}#${node_tag}-Trojan-${l}-80"
    echo "$trojan_80" >> nodes.txt
    proxy_names+=("${node_tag}-Trojan-${l}-80")
    cat>>clash.yaml<<EOF
  - name: "${node_tag}-Trojan-${l}-80"
    type: trojan
    server: ${d}
    port: 80
    password: ${uuid}
    udp: true
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${argo}
EOF
done

cat>>clash.yaml<<EOF
proxy-groups:
  - name: PROXY
    type: select
    proxies:
EOF

for pname in "${proxy_names[@]}"; do
    echo "      - \"${pname}\"" >> clash.yaml
done

cat>>clash.yaml<<EOF
rules:
  - MATCH,PROXY
EOF

if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
    base64 nodes.txt | tr -d '\n' > sub.txt
else
    base64 -w 0 nodes.txt > sub.txt
fi

server_ip=$(get_server_ip)
if [ -z "$server_ip" ]; then
    server_ip="$argo"
fi

sub_port=$[$RANDOM%10000+25000]
abs_dir=$(pwd)
start_sub_server "$abs_dir" "$sub_port"

sub_online_url="http://${server_ip}:${sub_port}/sub.txt"
clash_online_url="http://${server_ip}:${sub_port}/clash.yaml"

cat>v2ray.txt<<EOF
======================== 一键梭哈多节点列表 ========================
$(cat nodes.txt)

端口替换提示:
443 端口可替换为: 2053, 2083, 2087, 2096, 8443
80 端口可替换为:  8080, 8880, 2052, 2082, 2086, 2095

======================== 客户端订阅及导入链接 ========================
本机订阅服务运行在: ${server_ip}:${sub_port}

1. 通用订阅链接 (支持 v2rayN / NekoBox / Shadowrocket):
${sub_online_url}

2. v2rayN / NekoBox 一键导入协议链接:
sub://${sub_online_url}

3. Clash / Clash.Meta / Mihomo 一键导入配置:
clash://install-config?url=${clash_online_url}

4. Clash 在线配置文件直链:
${clash_online_url}

本地文件路径:
- 节点列表: ${abs_dir}/nodes.txt
- Base64 订阅: ${abs_dir}/sub.txt
- Clash 配置: ${abs_dir}/clash.yaml
=====================================================================
EOF

cat v2ray.txt
echo -e '\n信息已经保存在 v2ray.txt,再次查看请运行 cat v2ray.txt'
}

function installtunnel(){
mkdir -p /opt/suoha/ >/dev/null 2>&1
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
    x86_64 | x64 | amd64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
    ;;
    i386 | i686 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
    ;;
    armv8 | arm64 | aarch64 )
    echo arm64
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
    ;;
    armv7l )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
    ;;
    * )
    echo 当前架构$(uname -m)没有适配
    exit
    ;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
mv cloudflared-linux /opt/suoha/
mv xray/xray /opt/suoha/
rm -rf xray xray.zip
uuid=$(cat /proc/sys/kernel/random/uuid)
urlpath_vless="vl-$(echo $uuid | awk -F- '{print $1}')"
urlpath_trojan="tr-$(echo $uuid | awk -F- '{print $1}')"
port_vless=$[$RANDOM+10000]
port_trojan=$[$port_vless+1]

cat>/opt/suoha/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port_vless,
            "listen": "localhost",
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/$urlpath_vless"
                }
            }
        },
        {
            "port": $port_trojan,
            "listen": "localhost",
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/$urlpath_trojan"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF

clear
echo 复制下面的链接,用浏览器打开并授权需要绑定的域名
echo 在网页中授权完毕后会继续进行下一步设置
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel login
clear
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel list >argo.log 2>&1
echo -e ARGO TUNNEL当前已经绑定的服务如下'\n'
sed 1,2d argo.log | awk '{print $2}'
echo -e '\n'自定义一个完整二级域名,例如 xxx.example.com
echo 必须是网页里面绑定授权的域名才生效,不能乱输入
read -p "输入绑定域名的完整二级域名: " domain
if [ -z "$domain" ]
then
    echo 没有设置域名
    exit
elif [ $(echo $domain | grep "\." | wc -l) == 0 ]
then
    echo 域名格式不正确
    exit
fi
name=$(echo $domain | awk -F\. '{print $1}')
if [ $(sed 1,2d argo.log | awk '{print $2}' | grep -w $name | wc -l) == 0 ]
then
    echo 创建TUNNEL $name
    /opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >argo.log 2>&1
    echo TUNNEL $name 创建成功
else
    echo TUNNEL $name 已经存在
    if [ ! -f "/root/.cloudflared/$(sed 1,2d argo.log | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json" ]
    then
        echo /root/.cloudflared/$(sed 1,2d argo.log | awk '{print $1" "$2}' | grep -w $name | awk '{print $1}').json 文件不存在
        echo 清理TUNNEL $name
        /opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >argo.log 2>&1
        echo 删除TUNNEL $name
        /opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel delete $name >argo.log 2>&1
        echo 重建TUNNEL $name
        /opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel create $name >argo.log 2>&1
    else
        echo 清理TUNNEL $name
        /opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel cleanup $name >argo.log 2>&1
    fi
fi
echo 绑定 TUNNEL $name 到域名 $domain
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel route dns --overwrite-dns $name $domain >argo.log 2>&1
echo $domain 绑定成功
tunneluuid=$(cut -d= -f2 argo.log)

node_tag=$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')
if [[ -z "$node_tag" || "$node_tag" == "--" ]]; then
    node_tag="Argo_Node"
fi

domains=("$domain" "cf.090227.xyz" "cloudflare.182682.xyz")
labels=("自定域名" "优选cf.090227" "优选182682")

> /opt/suoha/nodes.txt

cat>/opt/suoha/clash.yaml<<EOF
port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
proxies:
EOF

proxy_names=()

for idx in "${!domains[@]}"; do
    d="${domains[$idx]}"
    l="${labels[$idx]}"

    vless_tls="vless://${uuid}@${d}:443?encryption=none&security=tls&sni=${domain}&type=ws&host=${domain}&path=%2F${urlpath_vless}#${node_tag}-VLESS-${l}-443"
    echo "$vless_tls" >> /opt/suoha/nodes.txt
    proxy_names+=("${node_tag}-VLESS-${l}-443")
    cat>>/opt/suoha/clash.yaml<<EOF
  - name: "${node_tag}-VLESS-${l}-443"
    type: vless
    server: ${d}
    port: 443
    uuid: ${uuid}
    cipher: auto
    tls: true
    udp: true
    servername: ${domain}
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${domain}
EOF

    vless_80="vless://${uuid}@${d}:80?encryption=none&security=none&type=ws&host=${domain}&path=%2F${urlpath_vless}#${node_tag}-VLESS-${l}-80"
    echo "$vless_80" >> /opt/suoha/nodes.txt
    proxy_names+=("${node_tag}-VLESS-${l}-80")
    cat>>/opt/suoha/clash.yaml<<EOF
  - name: "${node_tag}-VLESS-${l}-80"
    type: vless
    server: ${d}
    port: 80
    uuid: ${uuid}
    cipher: auto
    tls: false
    udp: true
    network: ws
    ws-opts:
      path: /${urlpath_vless}
      headers:
        Host: ${domain}
EOF

    trojan_tls="trojan://${uuid}@${d}:443?security=tls&sni=${domain}&type=ws&host=${domain}&path=%2F${urlpath_trojan}#${node_tag}-Trojan-${l}-443"
    echo "$trojan_tls" >> /opt/suoha/nodes.txt
    proxy_names+=("${node_tag}-Trojan-${l}-443")
    cat>>/opt/suoha/clash.yaml<<EOF
  - name: "${node_tag}-Trojan-${l}-443"
    type: trojan
    server: ${d}
    port: 443
    password: ${uuid}
    udp: true
    sni: ${domain}
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${domain}
EOF

    trojan_80="trojan://${uuid}@${d}:80?security=none&type=ws&host=${domain}&path=%2F${urlpath_trojan}#${node_tag}-Trojan-${l}-80"
    echo "$trojan_80" >> /opt/suoha/nodes.txt
    proxy_names+=("${node_tag}-Trojan-${l}-80")
    cat>>/opt/suoha/clash.yaml<<EOF
  - name: "${node_tag}-Trojan-${l}-80"
    type: trojan
    server: ${d}
    port: 80
    password: ${uuid}
    udp: true
    network: ws
    ws-opts:
      path: /${urlpath_trojan}
      headers:
        Host: ${domain}
EOF
done

cat>>/opt/suoha/clash.yaml<<EOF
proxy-groups:
  - name: PROXY
    type: select
    proxies:
EOF

for pname in "${proxy_names[@]}"; do
    echo "      - \"${pname}\"" >> /opt/suoha/clash.yaml
done

cat>>/opt/suoha/clash.yaml<<EOF
rules:
  - MATCH,PROXY
EOF

if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
    base64 /opt/suoha/nodes.txt | tr -d '\n' > /opt/suoha/sub.txt
else
    base64 -w 0 /opt/suoha/nodes.txt > /opt/suoha/sub.txt
fi

server_ip=$(get_server_ip)
if [ -z "$server_ip" ]; then
    server_ip="$domain"
fi

sub_port=$[$RANDOM%10000+25000]
start_sub_server "/opt/suoha" "$sub_port"

sub_online_url="http://${server_ip}:${sub_port}/sub.txt"
clash_online_url="http://${server_ip}:${sub_port}/clash.yaml"

cat>/opt/suoha/v2ray.txt<<EOF
======================== 节点连接信息 ========================
$(cat /opt/suoha/nodes.txt)

端口说明:
443 端口可替换为: 2053, 2083, 2087, 2096, 8443
80 端口可替换为:  8080, 8880, 2052, 2082, 2086, 2095

======================== 客户端订阅及导入链接 ========================
本机订阅服务运行在: ${server_ip}:${sub_port}

1. 通用在线订阅链接 (适用于 v2rayN / NekoBox / Shadowrocket):
${sub_online_url}

2. v2rayN / NekoBox 一键导入协议链接:
sub://${sub_online_url}

3. Clash / Clash.Meta / Mihomo 一键导入配置:
clash://install-config?url=${clash_online_url}

4. Clash 在线配置文件直链:
${clash_online_url}

本地文件路径:
- 节点列表: /opt/suoha/nodes.txt
- Base64 订阅: /opt/suoha/sub.txt
- Clash 配置: /opt/suoha/clash.yaml
==============================================================
EOF

rm -rf argo.log

cat>/opt/suoha/config.yaml<<EOF
tunnel: $tunneluuid
credentials-file: /root/.cloudflared/$tunneluuid.json

ingress:
  - hostname: $domain
    path: /$urlpath_vless
    service: http://localhost:$port_vless
  - hostname: $domain
    path: /$urlpath_trojan
    service: http://localhost:$port_trojan
  - service: http_status:404
EOF

if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
cat>/etc/local.d/cloudflared.start<<EOF
/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/suoha/config.yaml run $name &
EOF
cat>/etc/local.d/xray.start<<EOF
/opt/suoha/xray run -config /opt/suoha/config.json &
EOF
chmod +x /etc/local.d/cloudflared.start /etc/local.d/xray.start
rc-update add local
/etc/local.d/cloudflared.start >/dev/null 2>&1
/etc/local.d/xray.start >/dev/null 2>&1
else
cat>/lib/systemd/system/cloudflared.service<<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/suoha/cloudflared-linux --edge-ip-version $ips --protocol http2 tunnel --config /opt/suoha/config.yaml run $name
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
cat>/lib/systemd/system/xray.service<<EOF
[Unit]
Description=Xray
After=network.target

[Service]
TimeoutStartSec=0
Type=simple
ExecStart=/opt/suoha/xray run -config /opt/suoha/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable cloudflared.service >/dev/null 2>&1
systemctl enable xray.service >/dev/null 2>&1
systemctl --system daemon-reload
systemctl start cloudflared.service
systemctl start xray.service
fi

if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
then
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
while true
do
if [ \$(ps -ef | grep cloudflared-linux | grep -v grep | wc -l) == 0 ]
then
    argostatus=stop
else
    argostatus=running
fi
if [ \$(ps -ef | grep xray | grep -v grep | wc -l) == 0 ]
then
    xraystatus=stop
else
    xraystatus=running
fi
echo argo \$argostatus
echo xray \$xraystatus
echo 1.管理TUNNEL
echo 2.启动服务
echo 3.停止服务
echo 4.重启服务
echo 5.卸载服务
echo 6.查看当前订阅与节点链接
echo 0.退出
read -p "请选择菜单(默认0): " menu
if [ -z "\$menu" ]
then
    menu=0
fi
if [ \$menu == 1 ]
then
    clear
    while true
    do
        echo ARGO TUNNEL当前已经绑定的服务如下
        /opt/suoha/cloudflared-linux tunnel list
        echo 1.删除TUNNEL
        echo 0.退出
        read -p "请选择菜单(默认0): " tunneladmin
        if [ -z "\$tunneladmin" ]
        then
            tunneladmin=0
        fi
        if [ \$tunneladmin == 1 ]
        then
            read -p "请输入要删除的TUNNEL NAME: " tunnelname
            echo 断开TUNNEL \$tunnelname
            /opt/suoha/cloudflared-linux tunnel cleanup \$tunnelname
            echo 删除TUNNEL \$tunnelname
            /opt/suoha/cloudflared-linux tunnel delete \$tunnelname
        else
            break
        fi
    done
elif [ \$menu == 2 ]
then
    kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    /etc/local.d/cloudflared.start >/dev/null 2>&1
    /etc/local.d/xray.start >/dev/null 2>&1
    clear
    sleep 1
elif [ \$menu == 3 ]
then
    kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    clear
    sleep 2
elif [ \$menu == 4 ]
then
    kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    /etc/local.d/cloudflared.start >/dev/null 2>&1
    /etc/local.d/xray.start >/dev/null 2>&1
    clear
    sleep 1
elif [ \$menu == 5 ]
then
    kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$1}') >/dev/null 2>&1
    pkill -f "http.server" >/dev/null 2>&1
    rm -rf /opt/suoha /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/suoha ~/.cloudflared
    echo 所有服务都卸载完成
    echo 彻底删除授权记录
    echo 请访问 https://dash.cloudflare.com/profile/api-tokens
    echo 删除授权的 Argo Tunnel API Token 即可
    exit
elif [ \$menu == 6 ]
then
    clear
    cat /opt/suoha/v2ray.txt
elif [ \$menu == 0 ]
then
    echo 退出成功
    exit
fi
done
EOF
else
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
clear
while true
do
echo argo \$(systemctl status cloudflared.service | sed -n '3p')
echo xray \$(systemctl status xray.service | sed -n '3p')
echo 1.管理TUNNEL
echo 2.启动服务
echo 3.停止服务
echo 4.重启服务
echo 5.卸载服务
echo 6.查看当前订阅与节点链接
echo 0.退出
read -p "请选择菜单(默认0): " menu
if [ -z "\$menu" ]
then
    menu=0
fi
if [ \$menu == 1 ]
then
    clear
    while true
    do
        echo ARGO TUNNEL当前已经绑定的服务如下
        /opt/suoha/cloudflared-linux tunnel list
        echo 1.删除TUNNEL
        echo 0.退出
        read -p "请选择菜单(默认0): " tunneladmin
        if [ -z "\$tunneladmin" ]
        then
            tunneladmin=0
        fi
        if [ \$tunneladmin == 1 ]
        then
            read -p "请输入要删除的TUNNEL NAME: " tunnelname
            echo 断开TUNNEL \$tunnelname
            /opt/suoha/cloudflared-linux tunnel cleanup \$tunnelname
            echo 删除TUNNEL \$tunnelname
            /opt/suoha/cloudflared-linux tunnel delete \$tunnelname
        else
            break
        fi
    done
elif [ \$menu == 2 ]
then
    systemctl start cloudflared.service
    systemctl start xray.service
    clear
elif [ \$menu == 3 ]
then
    systemctl stop cloudflared.service
    systemctl stop xray.service
    clear
elif [ \$menu == 4 ]
then
    systemctl restart cloudflared.service
    systemctl restart xray.service
    clear
elif [ \$menu == 5 ]
then
    systemctl stop cloudflared.service
    systemctl stop xray.service
    systemctl disable cloudflared.service
    systemctl disable xray.service
    kill -9 \$(ps -ef | grep xray | grep -v grep | awk '{print \$2}') >/dev/null 2>&1
    kill -9 \$(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print \$2}') >/dev/null 2>&1
    pkill -f "http.server" >/dev/null 2>&1
    rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha ~/.cloudflared
    systemctl --system daemon-reload
    echo 所有服务都卸载完成
    echo 彻底删除授权记录
    echo 请访问 https://dash.cloudflare.com/profile/api-tokens
    echo 删除授权的 Argo Tunnel API Token 即可
    exit
elif [ \$menu == 6 ]
then
    clear
    cat /opt/suoha/v2ray.txt
elif [ \$menu == 0 ]
then
    echo 退出成功
    exit
fi
done
EOF
fi
chmod +x /opt/suoha/suoha.sh
ln -sf /opt/suoha/suoha.sh /usr/bin/suoha
}

clear
echo 梭哈模式不需要自己提供域名,使用CF ARGO QUICK TUNNEL创建快速链接
echo 梭哈模式在重启或者脚本再次运行后失效,如果需要使用需要再次运行创建
echo 安装服务模式,需要有CF托管域名,并且需要按照提示手动绑定ARGO服务
echo 首次绑定ARGO服务后如果不想再次跳转网页绑定
echo 将已经绑定的系统目录下的 /root/.cloudflared 文件夹以及内容
echo 拷贝至新系统下同样的目录,会自动跳过登录验证

echo -e '\n'梭哈是一种智慧!!!梭哈!梭哈!梭哈!梭哈!梭哈!梭哈!梭哈...'\n'
echo 1.梭哈模式 (自动生成 VLESS+Trojan 及所有优选节点)
echo 2.安装服务 (自定义域名绑定固定隧道)
echo 3.卸载服务
echo 4.清空缓存
echo -e 0.退出脚本'\n'
read -p "请选择模式(默认1):" mode
if [ -z "$mode" ]
then
    mode=1
fi
if [ $mode == 1 ]
then
    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    if [ -z "$ips" ]
    then
        ips=4
    fi
    if [ $ips != 4 ] && [ $ips != 6 ]
    then
        echo 请输入正确的argo连接模式
        exit
    fi
    isp=$(curl -$ips -s --connect-timeout 2 https://speed.cloudflare.com/meta 2>/dev/null | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
    if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
    then
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    rm -rf xray cloudflared-linux v2ray.txt nodes.txt sub.txt clash.yaml quick_tunnel.yaml
    quicktunnel
elif [ $mode == 2 ]
then
    read -p "请选择argo连接模式IPV4或者IPV6(输入4或6,默认4):" ips
    if [ -z "$ips" ]
    then
        ips=4
    fi
    if [ $ips != 4 ] && [ $ips != 6 ]
    then
        echo 请输入正确的argo连接模式
        exit
    fi
    isp=$(curl -$ips -s --connect-timeout 2 https://speed.cloudflare.com/meta 2>/dev/null | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
    if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
    then
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
    else
        systemctl stop cloudflared.service
        systemctl stop xray.service
        systemctl disable cloudflared.service
        systemctl disable xray.service
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
        systemctl --system daemon-reload
    fi
    installtunnel
    cat /opt/suoha/v2ray.txt
    echo 服务安装完成,管理服务请运行命令 suoha
elif [ $mode == 3 ]
then
    if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
    then
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        pkill -f "http.server" >/dev/null 2>&1
        rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha
    else
        systemctl stop cloudflared.service
        systemctl stop xray.service
        systemctl disable cloudflared.service
        systemctl disable xray.service
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        pkill -f "http.server" >/dev/null 2>&1
        rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha ~/.cloudflared
        systemctl --system daemon-reload
    fi
    clear
    echo 所有服务都卸载完成
    echo 彻底删除授权记录
    echo 请访问 https://dash.cloudflare.com/profile/api-tokens
    echo 删除授权的 Argo Tunnel API Token 即可
elif [ $mode == 4 ]
then
    if [ $(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}') == "Alpine" ]
    then
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $1}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep xray | grep -v grep | awk '{print $2}') >/dev/null 2>&1
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    pkill -f "http.server" >/dev/null 2>&1
    rm -rf xray cloudflared-linux v2ray.txt nodes.txt sub.txt clash.yaml quick_tunnel.yaml
else
    echo 退出成功
    exit
fi
