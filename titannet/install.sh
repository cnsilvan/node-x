#!/bin/bash

# 检查是否提供了hash参数
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hash>"
    exit 1
fi

HASH=$1

# 下载文件
curl -L -o titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz https://github.com/Titannet-dao/titan-node/releases/download/v0.1.19/titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz

# 创建目标文件夹并解压
tar -xzvf titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz

# 进入文件夹并复制文件
cd titan-edge_v0.1.19_89e53b6_linux_amd64
sudo cp titan-edge /usr/local/bin
sudo cp libgoworkerd.so /usr/local/lib

# 启动守护进程并绑定设备
titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0
titan-edge bind --hash=$HASH https://api-test1.container1.titannet.io/api/v2/device/binding

# 停止节点
# titan-edge daemon stop
