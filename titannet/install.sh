#!/bin/bash

# 检查是否提供了hash参数
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hash>"
    exit 1
fi

HASH=$1
echo "HASH=${HASH}"
# 下载文件
curl -L -o titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz https://github.com/Titannet-dao/titan-node/releases/download/v0.1.19/titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz
tar -xzvf titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz

# 进入文件夹并复制文件
cd titan-edge_v0.1.19_89e53b6_linux_amd64
sudo cp titan-edge /usr/local/bin
sudo cp libgoworkerd.so /usr/local/lib

# 更新共享库缓存
sudo ldconfig

# 创建 systemd 服务单元文件
cat <<EOL | sudo tee /etc/systemd/system/titan-edge.service
[Unit]
Description=Titan Edge Daemon Service
After=network.target

[Service]
ExecStart=/usr/local/bin/titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

# 重新加载 systemd 服务
sudo systemctl daemon-reload

# 启动并启用 titan-edge 服务
sudo systemctl start titan-edge
sudo systemctl enable titan-edge

# 绑定设备
titan-edge bind --hash=$HASH https://api-test1.container1.titannet.io/api/v2/device/binding
