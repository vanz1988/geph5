#!/bin/bash
set -e

echo "======================================"
echo "    一键部署 Geph5 Broker"
echo "======================================"

#------------------------------
# 1. 更新系统并安装依赖
#------------------------------
echo "[1/6] 安装依赖..."
sudo apt update -y
sudo apt install -y git curl build-essential pkg-config libssl-dev

#------------------------------
# 2. 安装 Rust
#------------------------------
echo "[2/6] 安装 Rust/Cargo..."
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi
echo "cargo version: $(cargo --version)"

#------------------------------
# 3. 克隆 Geph5 仓库
#------------------------------
echo "[3/6] 克隆 Geph5 仓库..."
cd /root
if [ -d geph5 ]; then
    rm -rf geph5
fi
git clone https://github.com/geph-official/geph5.git
cd geph5/binaries/geph5-broker

#------------------------------
# 4. 编译 Geph5-broker
#------------------------------
echo "[4/6] 编译 geph5-broker..."
cargo build --release

#------------------------------
# 5. 生成随机用户名、密码、密钥
#------------------------------
echo "[5/6] 生成配置文件..."
USER_NAME="user_$(head /dev/urandom | tr -dc a-z0-9 | head -c6)"
PASSWORD="$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c12)"
KEY="$(head /dev/urandom | tr -dc a-f0-9 | head -c32)"

sudo mkdir -p /etc/geph5
sudo tee /etc/geph5/broker_config.json > /dev/null <<EOF
{
  "listen": "0.0.0.0:443",
  "protocol": "geph5",
  "enable_udp": true,
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
# 6. 移动二进制并创建 systemd 服务
#------------------------------
echo "[6/6] 创建 systemd 服务..."
sudo cp target/release/geph5-broker /usr/local/bin/
sudo chmod +x /usr/local/bin/geph5-broker

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
echo "🎉 Geph5 Broker 部署完成！"
echo "用户名: $USER_NAME"
echo "密码: $PASSWORD"
echo "密钥: $KEY"
echo "配置文件: /etc/geph5/broker_config.json"
echo "状态查看: sudo systemctl status geph5-broker"
echo "======================================"
