#!/bin/bash
set -e

echo "======================================"
echo "   安全自建 Geph5 Broker 一键部署"
echo "======================================"

#------------------------------
# 1. 更新系统并安装依赖
#------------------------------
echo "[1/8] 安装依赖..."
sudo apt update -y
sudo apt install -y git curl build-essential pkg-config libssl-dev openssl ufw

#------------------------------
# 2. 安装 Rust
#------------------------------
echo "[2/8] 安装 Rust/Cargo..."
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi
echo "cargo version: $(cargo --version)"

#------------------------------
# 3. 克隆 Geph5 仓库
#------------------------------
echo "[3/8] 克隆 Geph5 仓库..."
cd /root
if [ -d geph5 ]; then
    rm -rf geph5
fi
git clone https://github.com/geph-official/geph5.git
cd geph5/binaries/geph5-broker

#------------------------------
# 4. 编译 Geph5-broker
#------------------------------
echo "[4/8] 编译 geph5-broker..."
cargo build --release

#------------------------------
# 5. 随机生成端口、用户名、密码、密钥
#------------------------------
echo "[5/8] 生成随机配置..."
PORT=$((RANDOM%64510+1025))  # 1025-65535
USER_NAME="user_$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
PASSWORD="$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c12)"
KEY="$(head /dev/urandom | tr -dc a-f0-9 | head -c32)"

#------------------------------
# 6. 自动生成自签名 TLS 证书
#------------------------------
echo "[6/8] 生成 TLS 证书..."
CERT_DIR=/etc/geph5/tls
sudo mkdir -p $CERT_DIR
sudo openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout $CERT_DIR/server.key \
    -out $CERT_DIR/server.crt \
    -subj "/CN=geph5-broker"

#------------------------------
# 7. 创建配置文件
#------------------------------
echo "[7/8] 写入 broker_config.json..."
sudo mkdir -p /etc/geph5
sudo tee /etc/geph5/broker_config.json > /dev/null <<EOF
{
  "listen": "0.0.0.0:$PORT",
  "protocol": "geph5",
  "enable_udp": true,
  "tls": {
    "cert": "$CERT_DIR/server.crt",
    "key": "$CERT_DIR/server.key"
  },
  "users": [
    {
      "username": "$USER_NAME",
      "password": "$PASSWORD",
      "key": "$KEY"
    }
  ]
}
EOF

#------------------------------
# 8. 移动二进制、配置防火墙并创建 systemd 服务
#------------------------------
echo "[8/8] 安装二进制并创建服务..."
sudo cp target/release/geph5-broker /usr/local/bin/
sudo chmod +x /usr/local/bin/geph5-broker

# 配置 ufw 防火墙
sudo ufw allow $PORT/tcp
sudo ufw allow $PORT/udp
sudo ufw --force enable

# 创建 systemd 服务
sudo tee /etc/systemd/system/geph5-broker.service > /dev/null <<EOF
[Unit]
Description=Geph5 Broker
After=network.target

[Service]
ExecStart=/usr/local/bin/geph5-broker --config /etc/geph5/broker_config.json
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable geph5-broker
sudo systemctl restart geph5-broker

#------------------------------
# 输出信息
#------------------------------
echo "======================================"
echo "🎉 Geph5 Broker 安全部署完成！"
echo "监听端口: $PORT"
echo "用户名: $USER_NAME"
echo "密码: $PASSWORD"
echo "密钥: $KEY"
echo "TLS 证书: $CERT_DIR/server.crt"
echo "配置文件: /etc/geph5/broker_config.json"
echo "查看状态: sudo systemctl status geph5-broker"
echo "======================================"
