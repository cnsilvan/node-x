#!/bin/bash

# 定义以 stv 用户执行命令的函数（修复参数传递）
run_as_stv() {
    # 使用数组传递参数，确保参数完整性
    local cmd_args=("$@")
    sudo -u stv /bin/bash -i -c "cd \$HOME && $(printf "%q " "${cmd_args[@]}")"
}

# 执行 stv redeem 并捕获输出
echo "正在执行节点检查..."
redeem_output=$(run_as_stv stv redeem 2>&1)
exit_code=$?

# 调试信息（可选）
echo "----- 调试信息 -----"
echo "命令退出码: $exit_code"
echo "原始输出:"
echo "$redeem_output"
echo "-------------------"

# 根据输出处理逻辑
if echo "$redeem_output" | grep -q "Node address has already been awarded"; then
    echo "✅ 节点已绑定，正在获取状态..."
    echo "========================================"
    echo "[网络状态]"
    run_as_stv stv -a status
    echo "----------------------------------------"
    echo "[节点状态]"
    run_as_stv stv node_status -a

elif echo "$redeem_output" | grep -q "https://redeem-mainnet.script.tv/?ssid="; then
    echo "🔗 未绑定节点，请操作："
    echo "$redeem_output"
    echo "========================================"
    echo "操作指引："
    echo "1. 打开上方链接 > 使用授权钱包登录"
    echo "2. 完成绑定后等待 1 分钟"
    echo "3. 重新运行本脚本检查状态"

else
    echo "❌ 严重错误，请检查以下问题：" >&2
    echo "$redeem_output" >&2
    echo "========================================" >&2
    echo "常见问题排查：" >&2
    echo "1. 确认 stv 用户已正确安装 CLI 工具"
    echo "2. 检查网络连接是否正常"
    echo "3. 手动验证命令是否可执行："
    echo "   sudo -u stv stv redeem"
    exit 1
fi
