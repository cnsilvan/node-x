#!/bin/bash

# 检查是否提供了hash参数
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hash>"
    exit 1
fi

HASH=$1
echo "HASH=${HASH}"
apt install jq -y
sudo systemctl stop titan-edge
# 下载文件
curl -L -o titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz https://github.com/Titannet-dao/titan-node/releases/download/v0.1.20/titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz
tar -xzvf titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz
# 复制文件
sudo cp titan-edge_v0.1.20_246b9dd_linux-amd64/titan-edge /usr/local/bin
sudo cp titan-edge_v0.1.20_246b9dd_linux-amd64/libgoworkerd.so /usr/local/lib
rm -rf titan-edge_v0.1.20_246b9dd_linux-amd64
rm titan-edge_v0.1.20_246b9dd_linux-amd64.tar.gz
# 更新共享库缓存
sudo ldconfig
# 获取当前登录用户
USER=$(whoami)
# 创建 systemd 服务单元文件
cat <<EOL | sudo tee /etc/systemd/system/titan-edge.service
[Unit]
Description=Titan Edge Daemon Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0
Restart=always
RestartSec=3
LimitNOFILE=4096
User=$USER

[Install]
WantedBy=multi-user.target
EOL



# 重新加载 systemd 服务
sudo systemctl daemon-reload

# 启动并启用 titan-edge 服务
sudo systemctl start titan-edge
sudo systemctl enable titan-edge

sleep 20
# 绑定设备
/usr/local/bin/titan-edge bind --hash=$HASH https://api-test1.container1.titannet.io/api/v2/device/binding
# 检查空闲磁盘空间，单位为GB
free_space=$(df / | grep / | awk '{print $4}')
free_space_gb=$((free_space / 1024 / 1024))
# 检查空闲空间是否大于100GB
if [ "$free_space_gb" -gt 100 ]; then
  echo "空闲磁盘空间大于100GB，正在执行命令..."
  sudo sed -i 's/^[[:space:]]*#StorageGB = .*/StorageGB = 20/' /root/.titanedge/config.toml
  sudo systemctl restart titan-edge
else
  echo "空闲磁盘空间不足100GB，当前空闲空间为${free_space_gb}GB。"
fi



