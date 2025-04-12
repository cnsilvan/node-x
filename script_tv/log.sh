#!/bin/bash

# 定义以 stv 用户执行命令的函数
run_as_stv() {
    sudo -u stv "$@"
}

# 执行 stv redeem 并捕获输出
redeem_output=$(run_as_stv stv redeem 2>&1)

# 情况1：检测到 "KO 40393 backend error"（已绑定）
if echo "$redeem_output" | grep -q "KO 40393 backend error. Received: Node address has already been awarded"; then
    echo "节点已绑定，正在获取状态信息..."
    echo "----------------------------------------"
    
    # 执行 stv -a status 并打印
    status_output=$(run_as_stv stv -a status)
    echo "[stv -a status 输出]"
    echo "$status_output"
    echo "----------------------------------------"
    
    # 执行 stv node_status 并打印
    node_status_output=$(run_as_stv stv node_status -a)
    echo "[stv node_status 输出]"
    echo "$node_status_output"

# 情况2：检测到 redeem 链接（未绑定）
elif echo "$redeem_output" | grep -q "https://redeem-mainnet.script.tv/?ssid="; then
    echo "$redeem_output"
    echo "----------------------------------------"
    echo "请前往上方地址完成绑定："
    echo "1. 使用你购买过许可的钱包登录"
    echo "2. 完成绑定后，等待1分钟"
    echo "3. 重新运行此脚本检查节点状态"

# 其他情况（异常）
else
    echo "未知响应:"
    echo "$redeem_output"
    exit 1
fi
