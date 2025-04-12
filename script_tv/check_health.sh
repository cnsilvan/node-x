#!/bin/bash
stv
# 初始化健康状态为 false
is_healthy=true

# 检查第一个条件：同步状态
if ! syncing_output=$(stv -a status 2>/dev/null); then
    echo "false"
    exit 0
fi

# 提取 syncing 状态
syncing=$(echo "$syncing_output" | grep -w 'syncing' | awk '{print $2}')
if [[ "$syncing" != "false" ]]; then
    is_healthy=false
fi

# 提取并验证 current_height 和 explorer_progress_height
current_height=$(echo "$syncing_output" | grep -w 'current_height' | awk '{print $2}')
explorer_height=$(echo "$syncing_output" | grep -w 'explorer_progress_height' | awk '{print $2}')

if [[ -z "$current_height" || -z "$explorer_height" ]] || 
   ! [[ "$current_height" =~ ^[0-9]+$ && "$explorer_height" =~ ^[0-9]+$ ]]; then
    is_healthy=false
else
    # 计算高度差绝对值
    diff=$((current_height - explorer_height))
    if [[ ${diff#-} -gt 10 ]]; then
        is_healthy=false
    fi
fi

# 检查第二个条件：节点状态摘要
if ! node_status_output=$(stv node_status -a 2>/dev/null); then
    echo "false"
    exit 0
fi

node_status_line=$(echo "$node_status_output" | grep 'Node status summary:')
if [[ -z "$node_status_line" ]]; then
    is_healthy=false
else
    node_status=$(echo "$node_status_line" | awk -F': ' '{print $2}' | xargs)
    if [[ "$node_status" != "Node is a"* ]]; then
        is_healthy=false
    fi
fi

# 最终输出结果
if [[ "$is_healthy" == "true" ]]; then
    echo "true"
else
    echo "false"
fi
