#!/usr/bin/env bash

if [[ ! -d /opt/tuic ]]; then
    echo
    echo "创建文件夹"
    mkdir -p /opt/tuic && cd /opt/tuic
else
    echo
    echo "文件夹已存在  "
    cd /opt/tuic
fi

echo
if tyoe jq >/dev/null 2>&1; then
    echo
    echo "jq 已安装  "
else
    echo "安装 jq"
    apt install jq -y >/dev/null 2>&1 || yum install jq -y >/dev/null 2>&1
fi

echo
echo "正在安装依赖..."
echo
if typr wget certbot >/dev/null 2>&1; then
    echo "依赖已安装 "
else

    echo
    echo "依赖未安装"
    if [[ -f /etc/redhat-release ]]; then
        yum install wget certbot -y
    else
        apt install wget certbot -y
    fi
fi
echo
echo
if type node </dev/null >/dev/null 2>&1; then
    echo "已安装nodejs "
else
    echo "正在安装nodejs"
    if type apt >/dev/null 2>&1; then
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
        apt install -y nodejs
    elif type yum >/dev/null 2>&1; then
        curl -sL https://rpm.nodesource.com/setup_16.x | bash -
        yum install -y nodejs
    else
        echo "不支持的操作系统！"
        exit 1
    fi
fi
echo
echo "安装 pm2"
echo
if type pm2 </dev/null >/dev/null 2>&1; then
    echo "已安装pm2 "
else
    echo
    echo "正在安装pm2"
    npm install pm2 -g
fi

echo
OS_ARCH=$(arch)
if [[ ${OS_ARCH} == "x86_64" || ${OS_ARCH} == "x64" || ${OS_ARCH} == "amd64" ]]; then
    OS_ARCH="x86_64"
    echo
    echo "当前系统架构为 ${OS_ARCH}"
elif [[ ${OS_ARCH} == "aarch64" || ${OS_ARCH} == "aarch64" ]]; then
    OS_ARCH="aarch64"
    echo "当前系统架构为 ${OS_ARCH}"
else
    echo
    OS_ARCH="amd64"
    echo "检测系统架构失败，使用默认架构: ${OS_ARCH}"
fi
echo

echo "正在下载tuic..."
echo
if [[ -f /opt/tuic/tuic-server-0.8.5 ]]; then
    echo
    echo "tuic-server-0.8.5 已存在 "

else
    tag=$(wget -qO- -t1 -T2 "https://api.github.com/repos/EAimTY/tuic/releases/latest" | jq -r '.tag_name')
    echo
    echo "最新版本为 ${tag}"
    echo
    echo "正在下载tuic-server-&{tag}..."
    echo
    wget https://github.com/EAimTY/tuic/releases/download/${tag}/tuic-server-${tag}-${OS_ARCH}-linux-gnu -O tuic-server-${tag} && chmod +x tuic-server-${tag}
fi

echo
echo "申请证书..."
if [[ -f /opt/tuic/fullchain.pem ]]; then
    echo
    echo "证书已申请 "
else
    echo
    echo "正在申请证书..."
    echo
    read -p "请输入域名: " DOMAIN
    echo
    read -p "请输入邮箱:(默认jhyIYF233G@google.com)" EMAIL
    certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        --email ${EMAIL:-jhyIYF233G@google.com} \
        -d ${DOMAIN}
    echo
    echo "${DOMAIN}" >/opt/tuic/domain.txt
    echo
    cp /etc/letsencrypt/live/${DOMAIN}/*.pem /opt/tuic/
fi

echo
echo "正在创建配置文件..."

if [[ -f /opt/tuic/tuic.conf ]]; then
    echo
    echo "配置文件已存在"
    echo
else
    echo "正在创建配置文件"

    echo
    read -p "请输入密码:(默认123456) " password
    echo

    read -p "请输入端口:(默认52345)" port
    echo
    echo
    cat >/opt/tuic/tuic.conf <<EOF
{
    "port": ${port:-52345},
    "token": ["${password:-123456}"],
    "certificate": "/opt/tuic/fullchain.pem",
    "private_key": "/opt/tuic/privkey.pem",
    "ip": "0.0.0.0",
    "congestion_controller": "bbr",
    "alpn": ["h3"]
}
EOF

fi
echo "正在启动tuic-server..."
if [[ $(pm2 ls | grep tuic | wc -l) -gt 0 ]]; then
    echo
    echo "tuic-server 已经运行...  "
    pm2 ls
    echo
else
    echo
    echo "正在启动tuic-server ..."
    pm2 start ./tuic-server-0.8.5 -n tuic -- -c tuic.conf
fi

echo
echo "开机自启动..."
echo
pm2 save && pm2 startup systemd && systemctl enable pm2-root && systemctl start pm2-root
echo
echo "正在读取 tuic-server-0.8.5 运行日志..."

echo
pm2 log tuic --lines 10 --raw --nostream
echo
echo "配置 tuic ssl 证书指纹 "
echo
echo "$(cd /opt/tuic && openssl x509 -fingerprint -sha256 -in fullchain.pem -noout | cut -d = -f 2)"
echo
echo
echo "============ surge 简易配置示例 =============="
echo
echo "surge tuic = tuic, $(curl https://api.my-ip.io/ip -s), $(cat /opt/tuic/tuic.conf | jq -r '.port'),sni=$(cat /opt/tuic/domain.txt),server-cert-fingerprint-sha256=$(cd /opt/tuic && openssl x509 -fingerprint -sha256 -in fullchain.pem -noout | cut -d = -f 2),token=$(cat /opt/tuic/tuic.conf | jq -r '.token[0]'),alpn=h3"
echo
echo "============================================"
echo
echo
echo "============ stash 简易配置示例 =============="
echo "
  - name: stash tuic
    type: tuic
    server: $(curl https://api.my-ip.io/ip -s)
    port: $(cat /opt/tuic/tuic.conf | jq -r '.port')
    token: "$(cat /opt/tuic/tuic.conf | jq -r '.token[0]')"
    udp: true
    skip-cert-verify: true
    sni: "$(cat /opt/tuic/domain.txt)"
    alpn:
      - h3"
echo
echo "=============================================="
echo
echo "tuic-server-0.8.5  安装完成 "
echo
