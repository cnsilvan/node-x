#!/bin/bash

# Bitcoin节点管理脚本 (多系统支持版本)
# 支持系统: Ubuntu/Debian, CentOS/RHEL/Rocky/AlmaLinux, macOS
# 使用方法: ./bitcoin_node.sh [--force] [--prune] [install|status|health|restart|stop|uninstall|logs|sync|rpc-url] [mainnet|testnet]
# 远程执行: curl -fsSL https://raw.githubusercontent.com/your-repo/btc_node.sh | bash -s -- install
# 环境变量:
# BITCOIN_NETWORK: mainnet 或 testnet (默认: mainnet)
# BITCOIN_DATA_DIR: 数据目录 (默认: ~/.bitcoin)
# BITCOIN_USER: 运行用户 (默认: 当前用户)
# BITCOIN_PRUNE: 修剪模式 (默认: false)

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


# 默认配置
BITCOIN_NETWORK=${BITCOIN_NETWORK:-"mainnet"}
BITCOIN_USER=${BITCOIN_USER:-$(whoami)}
BITCOIN_DATA_DIR=${BITCOIN_DATA_DIR:-"$HOME/.bitcoin"}
BITCOIN_VERSION="28.1"
BITCOIN_SERVICE_NAME="bitcoind"
FORCE_MODE=false
PRUNE_MODE=false
FORCE_RESTART=false
SKIP_RESTART=false

# 修剪模式配置 (GB) - 根据网络类型设置不同默认值
# 将在网络类型确定后重新设置
PRUNE_SIZE_GB=${PRUNE_SIZE_GB:-0}  # 0表示使用默认值，将根据网络类型设置

# 注意：Bitcoin Core的prune参数单位是MiB (mebibytes)
# 1 GB ≈ 953.67 MiB，所以需要正确换算
# PRUNE_SIZE_MB将在网络类型确定后计算

# 系统相关变量 (将在detect_os()中设置)
OS_ID=""
OS_FAMILY=""
PACKAGE_MANAGER=""
SERVICE_MANAGER=""
ARCH=""
# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v lsb_release >/dev/null 2>&1; then
            OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        elif [ -f /etc/os-release ]; then
            OS_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        elif [ -f /etc/redhat-release ]; then
            OS_ID="centos"
        else
            OS_ID="unknown"
        fi
        
        case "$OS_ID" in
            ubuntu|debian)
                OS_FAMILY="debian"
                PACKAGE_MANAGER="apt"
                ;;
            centos|rhel|rocky|almalinux|fedora)
                OS_FAMILY="redhat"
                PACKAGE_MANAGER="yum"
                if command -v dnf >/dev/null 2>&1; then
                    PACKAGE_MANAGER="dnf"
                fi
                ;;
            *)
                OS_FAMILY="unknown"
                PACKAGE_MANAGER="unknown"
                ;;
        esac
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        OS_ID="macos"
        OS_FAMILY="darwin"
        PACKAGE_MANAGER="brew"
    else
        # 其他系统
        OS_ID="unknown"
        OS_FAMILY="unknown"
        PACKAGE_MANAGER="unknown"
    fi
    
    log_info "检测到操作系统: $OS_ID ($OS_FAMILY)"
}

# 检测CPU架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            log_error "不支持的CPU架构: $arch"
            exit 1
            ;;
    esac
    log_info "检测到CPU架构: $ARCH"
}

# 多系统包安装函数
install_packages() {
    local packages="$1"
    log_info "安装系统依赖包..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            sudo apt update
            sudo apt install -y $packages
            ;;
        yum|dnf)
            sudo $PACKAGE_MANAGER update -y
            sudo $PACKAGE_MANAGER install -y $packages
            ;;
        brew)
            # macOS使用Homebrew
            if ! command -v brew >/dev/null 2>&1; then
                log_error "请先安装Homebrew: https://brew.sh"
                exit 1
            fi
            brew install $packages
            ;;
        *)
            log_error "不支持的包管理器: $PACKAGE_MANAGER"
            exit 1
            ;;
    esac
}

# 检查并安装必要工具
check_dependencies() {
    local missing_tools=()
    
    # 检查基础工具
    for tool in wget curl bc jq tar; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing_tools+=($tool)
        fi
    done
    
    # 如果有缺失的工具，安装它们
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_info "安装缺失的工具: ${missing_tools[*]}"
        case "$OS_FAMILY" in
            debian)
                install_packages "${missing_tools[*]}"
                ;;
            redhat)
                # CentOS/RHEL可能需要特殊处理
                local redhat_packages=""
                for tool in "${missing_tools[@]}"; do
                    case "$tool" in
                        bc) redhat_packages="$redhat_packages bc" ;;
                        jq) redhat_packages="$redhat_packages jq" ;;
                        *) redhat_packages="$redhat_packages $tool" ;;
                    esac
                done
                install_packages "$redhat_packages"
                ;;
            darwin)
                install_packages "${missing_tools[*]}"
                ;;
        esac
    fi
}

# 获取系统服务管理器类型
get_service_manager() {
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
    elif command -v launchctl >/dev/null 2>&1; then
        SERVICE_MANAGER="launchd"  # macOS
    elif command -v service >/dev/null 2>&1; then
        SERVICE_MANAGER="sysv"
    else
        SERVICE_MANAGER="none"
        log_warn "未检测到服务管理器，将使用手动启动方式"
    fi
    log_info "服务管理器: $SERVICE_MANAGER"
}
# 初始化系统检测
detect_os
detect_arch
get_service_manager
check_dependencies

# 根据网络类型设置配置
if [ "$BITCOIN_NETWORK" = "testnet" ]; then
    BITCOIN_CONF_FILE="$BITCOIN_DATA_DIR/bitcoin.conf"
    BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/testnet3/debug.log"
    BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/testnet3/bitcoind.pid"
    DEFAULT_RPC_PORT="18332"
    
    # 设置测试网默认修剪大小
    if [ "$PRUNE_SIZE_GB" -eq 0 ]; then
        PRUNE_SIZE_GB=20  # 测试网默认保留20GB
    fi
    
    # 测试网修剪大小合理性检查
    TESTNET_FULL_SIZE=80  # 测试网全节点约80GB
    if [ "$PRUNE_MODE" = "true" ] && [ "$PRUNE_SIZE_GB" -gt "$TESTNET_FULL_SIZE" ]; then
        log_error "修剪大小($PRUNE_SIZE_GB GB)大于测试网全节点大小(约$TESTNET_FULL_SIZE GB)"
        log_info "建议："
        log_info "1. 设置更小的修剪大小."
        log_info "2. 使用全节点模式."
        exit 1
    fi
else
    BITCOIN_CONF_FILE="$BITCOIN_DATA_DIR/bitcoin.conf"
    BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/debug.log"
    BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/bitcoind.pid"
    DEFAULT_RPC_PORT="8332"
    
    # 设置主网默认修剪大小
    if [ "$PRUNE_SIZE_GB" -eq 0 ]; then
        PRUNE_SIZE_GB=50  # 主网默认保留50GB
    fi
    
    # 主网修剪大小合理性检查
    MAINNET_FULL_SIZE=800  # 主网全节点约800GB+
    if [ "$PRUNE_MODE" = "true" ] && [ "$PRUNE_SIZE_GB" -gt "$MAINNET_FULL_SIZE" ]; then
        log_error "修剪大小($PRUNE_SIZE_GB GB)大于主网全节点大小(约$MAINNET_FULL_SIZE GB)"
        log_info "建议："
        log_info "1. 设置更小的修剪大小."
        log_info "2. 使用全节点模式."
        exit 1
    fi
fi

# 计算修剪大小的MB值用于Bitcoin Core配置
PRUNE_SIZE_MB=$((PRUNE_SIZE_GB * 1024))

# 获取RPC连接信息
get_rpc_info() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi

    # 从配置文件读取RPC信息
    local rpc_user=$(grep "^rpcuser=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    local rpc_password=$(grep "^rpcpassword=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    
    # 根据网络类型读取端口和绑定地址
    local rpc_port=""
    local rpc_bind=""
    
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        # 测试网从[test]节读取所有RPC配置
        rpc_port=$(awk '/^\[test\]/{flag=1;next}/^\[/{flag=0}flag && /^rpcport=/{print $0}' "$BITCOIN_CONF_FILE" | cut -d'=' -f2 | head -n1)
        rpc_bind=$(awk '/^\[test\]/{flag=1;next}/^\[/{flag=0}flag && /^rpcbind=/{print $0}' "$BITCOIN_CONF_FILE" | cut -d'=' -f2 | head -n1)
        
        # 如果没有找到，使用默认值
        if [ -z "$rpc_port" ]; then
            rpc_port="$DEFAULT_RPC_PORT"
        fi
        if [ -z "$rpc_bind" ]; then
            rpc_bind="0.0.0.0"
        fi
    else
        # 主网从全局配置读取
        rpc_port=$(grep "^rpcport=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "$DEFAULT_RPC_PORT")
        rpc_bind=$(grep "^rpcbind=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 | head -n1 || echo "0.0.0.0")
    fi

    # 检查必要信息是否存在
    if [ -z "$rpc_user" ] || [ -z "$rpc_password" ]; then
        log_error "RPC用户名或密码未在配置文件中找到"
        return 1
    fi

    echo "$rpc_user:$rpc_password:$rpc_bind:$rpc_port"
}

# 显示RPC连接URL
show_rpc_url() {
    log_info "获取Bitcoin节点RPC连接信息..."

    # 检查节点是否运行
    if ! pgrep bitcoind >/dev/null 2>&1; then
        log_error "Bitcoin节点未运行，请先启动节点"
        return 1
    fi

    # 获取RPC信息
    local rpc_info=$(get_rpc_info)
    if [ $? -ne 0 ]; then
        return 1
    fi

    local rpc_user=$(echo "$rpc_info" | cut -d':' -f1)
    local rpc_password=$(echo "$rpc_info" | cut -d':' -f2)
    local rpc_host=$(echo "$rpc_info" | cut -d':' -f3)
    local rpc_port=$(echo "$rpc_info" | cut -d':' -f4)
    
    # 获取IP地址信息
    local local_ip=$(get_local_ip)
    local public_ip=$(get_public_ip)

    # 检测实际网络类型
    local actual_network=$(detect_actual_network)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}Bitcoin节点RPC连接信息${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}网络类型:${NC} $actual_network"
    echo -e "${YELLOW}RPC端口:${NC} $rpc_port"
    echo -e "${YELLOW}RPC用户:${NC} $rpc_user"
    echo -e "${YELLOW}RPC密码:${NC} $rpc_password"
    echo ""
    echo -e "${GREEN}连接地址信息:${NC}"
    echo -e "${YELLOW}本地连接:${NC} 127.0.0.1:$rpc_port"
    if [ -n "$local_ip" ]; then
        echo -e "${YELLOW}局域网连接:${NC} $local_ip:$rpc_port"
    fi
    if [ -n "$public_ip" ]; then
        echo -e "${YELLOW}公网连接:${NC} $public_ip:$rpc_port"
    else
        echo -e "${YELLOW}公网连接:${NC} 无法获取公网IP (检查网络连接)"
    fi
    
    # 显示配置模式信息
    if grep -q "^prune=" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        local prune_size=$(grep "^prune=" "$BITCOIN_CONF_FILE" | cut -d'=' -f2)
        local prune_gb=$((prune_size / 1024))
        echo -e "${YELLOW}修剪模式:${NC} 启用 (保留${prune_gb}GB区块数据)"
    else
        echo -e "${YELLOW}修剪模式:${NC} 禁用 (保留完整区块链)"
    fi
    
    if grep -q "^disablewallet=1" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        echo -e "${YELLOW}钱包功能:${NC} 禁用"
    else
        echo -e "${YELLOW}钱包功能:${NC} 启用"
    fi
    
    # 显示网络配置 - 基于实际配置文件 (重用之前检测的结果)
    if [ "$actual_network" = "testnet" ]; then
        echo -e "${YELLOW}网络配置:${NC} 测试网 (RPC配置在[test]节中)"
    elif [ "$actual_network" = "mainnet" ]; then
        echo -e "${YELLOW}网络配置:${NC} 主网 (RPC配置在全局)"
    else
        echo -e "${YELLOW}网络配置:${NC} 未知 (配置文件异常)"
    fi
    
    echo ""
    echo -e "${GREEN}RPC连接URL:${NC}"
    echo -e "${YELLOW}本地连接:${NC} http://${rpc_user}:${rpc_password}@127.0.0.1:${rpc_port}/"
    
    # 获取实际绑定地址来决定显示哪些连接选项
    local config_info=$(get_actual_rpc_config)
    if [ "$config_info" != "config_not_found" ]; then
        local actual_bind=$(echo "$config_info" | cut -d':' -f1)
        
        if [ "$actual_bind" = "0.0.0.0" ]; then
            # 绑定到所有接口，显示局域网和公网连接
            if [ -n "$local_ip" ]; then
                echo -e "${YELLOW}局域网连接:${NC} http://${rpc_user}:${rpc_password}@${local_ip}:${rpc_port}/"
            fi
            if [ -n "$public_ip" ]; then
                echo -e "${YELLOW}公网连接:${NC} http://${rpc_user}:${rpc_password}@${public_ip}:${rpc_port}/"
            fi
        elif [ "$actual_bind" != "127.0.0.1" ]; then
            # 绑定到特定IP
            echo -e "${YELLOW}绑定地址连接:${NC} http://${rpc_user}:${rpc_password}@${actual_bind}:${rpc_port}/"
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${GREEN}使用示例:${NC}"
    echo ""
    echo -e "${YELLOW}curl命令示例 (本地):${NC}"
    echo "curl -u \"$rpc_user:$rpc_password\" -d '{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'content-type: text/plain;' http://127.0.0.1:$rpc_port/"
    
    # 基于实际绑定地址显示相应示例
    if [ "$config_info" != "config_not_found" ]; then
        local actual_bind=$(echo "$config_info" | cut -d':' -f1)
        
        if [ "$actual_bind" = "0.0.0.0" ] && [ -n "$public_ip" ]; then
            echo ""
            echo -e "${YELLOW}curl命令示例 (公网):${NC}"
            echo "curl -u \"$rpc_user:$rpc_password\" -d '{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'content-type: text/plain;' http://$public_ip:$rpc_port/"
        elif [ "$actual_bind" != "127.0.0.1" ]; then
            echo ""
            echo -e "${YELLOW}curl命令示例 (绑定地址):${NC}"
            echo "curl -u \"$rpc_user:$rpc_password\" -d '{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'content-type: text/plain;' http://$actual_bind:$rpc_port/"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Python示例 (本地):${NC}"
    echo "import requests"
    echo "rpc_url = 'http://${rpc_user}:${rpc_password}@127.0.0.1:${rpc_port}/'"
    echo "payload = {\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}"
    echo "response = requests.post(rpc_url, json=payload)"
    echo "print(response.json())"
    
    # 基于实际绑定地址显示相应示例
    if [ "$config_info" != "config_not_found" ]; then
        local actual_bind=$(echo "$config_info" | cut -d':' -f1)
        
        if [ "$actual_bind" = "0.0.0.0" ] && [ -n "$public_ip" ]; then
            echo ""
            echo -e "${YELLOW}Python示例 (公网):${NC}"
            echo "import requests"
            echo "rpc_url = 'http://${rpc_user}:${rpc_password}@${public_ip}:${rpc_port}/'"
            echo "payload = {\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}"
            echo "response = requests.post(rpc_url, json=payload)"
            echo "print(response.json())"
        elif [ "$actual_bind" != "127.0.0.1" ]; then
            echo ""
            echo -e "${YELLOW}Python示例 (绑定地址):${NC}"
            echo "import requests"
            echo "rpc_url = 'http://${rpc_user}:${rpc_password}@${actual_bind}:${rpc_port}/'"
            echo "payload = {\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}"
            echo "response = requests.post(rpc_url, json=payload)"
            echo "print(response.json())"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Node.js示例 (本地):${NC}"
    echo "const axios = require('axios');"
    echo "const rpcUrl = 'http://${rpc_user}:${rpc_password}@127.0.0.1:${rpc_port}/';"
    echo "const payload = {jsonrpc:'1.0',id:'test',method:'getblockchaininfo',params:[]};"
    echo "axios.post(rpcUrl, payload).then(res => console.log(res.data));"
    
    # 基于实际绑定地址显示相应示例
    if [ "$config_info" != "config_not_found" ]; then
        local actual_bind=$(echo "$config_info" | cut -d':' -f1)
        
        if [ "$actual_bind" = "0.0.0.0" ] && [ -n "$public_ip" ]; then
            echo ""
            echo -e "${YELLOW}Node.js示例 (公网):${NC}"
            echo "const axios = require('axios');"
            echo "const rpcUrl = 'http://${rpc_user}:${rpc_password}@${public_ip}:${rpc_port}/';"
            echo "const payload = {jsonrpc:'1.0',id:'test',method:'getblockchaininfo',params:[]};"
            echo "axios.post(rpcUrl, payload).then(res => console.log(res.data));"
        elif [ "$actual_bind" != "127.0.0.1" ]; then
            echo ""
            echo -e "${YELLOW}Node.js示例 (绑定地址):${NC}"
            echo "const axios = require('axios');"
            echo "const rpcUrl = 'http://${rpc_user}:${rpc_password}@${actual_bind}:${rpc_port}/';"
            echo "const payload = {jsonrpc:'1.0',id:'test',method:'getblockchaininfo',params:[]};"
            echo "axios.post(rpcUrl, payload).then(res => console.log(res.data));"
        fi
    fi
    echo ""
    
    # 测试RPC连接
    echo -e "${GREEN}连接测试:${NC}"
    if command -v bitcoin-cli >/dev/null 2>&1; then
        local test_result=$(bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getblockchaininfo 2>/dev/null)
        if [ $? -eq 0 ]; then
            local blocks=$(echo "$test_result" | jq -r '.blocks // "未知"' 2>/dev/null || echo "未知")
            local network=$(echo "$test_result" | jq -r '.chain // "未知"' 2>/dev/null || echo "未知")
            echo -e "${GREEN}✓ RPC连接正常${NC}"
            echo -e "  当前区块高度: $blocks"
            echo -e "  网络: $network"
        else
            echo -e "${RED}✗ RPC连接失败${NC}"
        fi
    else
        echo -e "${YELLOW}! 无法测试连接 (bitcoin-cli未找到)${NC}"
    fi
    echo ""
    
    # 基于实际配置的安全提示
    generate_security_warning
}

# 仅返回RPC URL (用于脚本调用)
get_rpc_url_only() {
    local rpc_info=$(get_rpc_info 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi

    local rpc_user=$(echo "$rpc_info" | cut -d':' -f1)
    local rpc_password=$(echo "$rpc_info" | cut -d':' -f2)
    local rpc_host=$(echo "$rpc_info" | cut -d':' -f3)
    local rpc_port=$(echo "$rpc_info" | cut -d':' -f4)

    # 默认返回本地连接，避免安全风险
    echo "http://${rpc_user}:${rpc_password}@127.0.0.1:${rpc_port}/"
}

# RPC配置管理函数

# 从配置文件检测实际的网络类型
detect_actual_network() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        echo "unknown"
        return 1
    fi
    
    # 检查配置文件中是否有testnet=1
    if grep -q "^testnet=1" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        echo "testnet"
    else
        echo "mainnet"
    fi
}

# 从配置文件读取实际的RPC配置
get_actual_rpc_config() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        echo "config_not_found"
        return 1
    fi
    
    local actual_bind=""
    local actual_allowip=""
    local has_auth="true"
    local actual_network=$(detect_actual_network)
    
    if [ "$actual_network" = "testnet" ]; then
        # 测试网：从[test]节读取
        actual_bind=$(awk '/^\[test\]/{flag=1;next}/^\[/{flag=0}flag && /^rpcbind=/{print $0}' "$BITCOIN_CONF_FILE" | cut -d'=' -f2 | head -n1)
        actual_allowip=$(awk '/^\[test\]/{flag=1;next}/^\[/{flag=0}flag && /^rpcallowip=/{print $0}' "$BITCOIN_CONF_FILE" | cut -d'=' -f2 | head -n1)
    else
        # 主网：从全局配置读取
        actual_bind=$(grep "^rpcbind=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 | head -n1)
        actual_allowip=$(grep "^rpcallowip=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 | head -n1)
    fi
    
    # 检查是否有认证配置
    if ! grep -q "^rpcuser=" "$BITCOIN_CONF_FILE" 2>/dev/null || ! grep -q "^rpcpassword=" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        has_auth="false"
    fi
    
    # 设置默认值
    if [ -z "$actual_bind" ]; then
        actual_bind="127.0.0.1"
    fi
    if [ -z "$actual_allowip" ]; then
        actual_allowip="127.0.0.1"
    fi
    
    echo "$actual_bind:$actual_allowip:$has_auth"
}

# 生成基于实际配置的安全提示
generate_security_warning() {
    local config_info=$(get_actual_rpc_config)
    if [ "$config_info" = "config_not_found" ]; then
        echo -e "${RED}⚠️  警告: 配置文件未找到${NC}"
        return
    fi
    
    local actual_bind=$(echo "$config_info" | cut -d':' -f1)
    local actual_allowip=$(echo "$config_info" | cut -d':' -f2)
    local has_auth=$(echo "$config_info" | cut -d':' -f3)
    
    echo -e "${GREEN}当前RPC安全配置:${NC}"
    echo -e "  绑定地址: $actual_bind"
    echo -e "  允许IP: $actual_allowip"
    echo -e "  认证状态: $([ "$has_auth" = "true" ] && echo "已启用" || echo "已禁用")"
    echo ""
    
    # 根据实际配置生成安全提示
    if [ "$actual_bind" = "0.0.0.0" ]; then
        echo -e "${RED}⚠️  安全警告: 高风险配置${NC}"
        echo "• RPC绑定到所有接口 (0.0.0.0)，允许外部访问"
        if [ "$actual_allowip" = "0.0.0.0/0" ]; then
            echo -e "${RED}• 允许任何IP访问，风险极高！${NC}"
        else
            echo "• 允许特定IP访问: $actual_allowip"
        fi
        echo ""
        echo "建议的安全措施:"
        echo "  - 使用防火墙限制访问源"
        echo "  - 定期更换RPC密码"
        echo "  - 考虑使用VPN或SSH隧道"
        echo "  - 生产环境建议绑定到特定IP"
        if [ "$has_auth" = "false" ]; then
            echo -e "  - ${RED}立即启用RPC认证！${NC}"
        fi
    elif [ "$actual_bind" = "127.0.0.1" ]; then
        echo -e "${GREEN}✅ 安全配置: 低风险${NC}"
        echo "• RPC仅绑定到本地 (127.0.0.1)"
        echo "• 仅允许本机访问，安全性较高"
        if [ "$has_auth" = "false" ]; then
            echo -e "${YELLOW}• 注意: 未启用RPC认证${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  中等风险配置${NC}"
        echo "• RPC绑定到特定地址: $actual_bind"
        echo "• 允许的IP: $actual_allowip"
        echo ""
        echo "建议:"
        echo "  - 确保防火墙配置正确"
        echo "  - 定期检查访问日志"
        if [ "$has_auth" = "false" ]; then
            echo -e "  - ${YELLOW}建议启用RPC认证${NC}"
        fi
    fi
    echo ""
}

# 获取重启模式
get_restart_mode() {
    local restart_mode=""
    if [ "$FORCE_RESTART" = "true" ]; then
        restart_mode="true"
    elif [ "$SKIP_RESTART" = "true" ]; then
        restart_mode="false"
    fi
    echo "$restart_mode"
}

# 验证IP地址格式
validate_ip() {
    local ip="$1"
    # 支持IP地址、CIDR和特殊值
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || [[ "$ip" == "127.0.0.1" ]] || [[ "$ip" == "0.0.0.0/0" ]]; then
        return 0
    else
        return 1
    fi
}

# 备份配置文件
backup_config() {
    local backup_file="${BITCOIN_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$BITCOIN_CONF_FILE" "$backup_file"
    log_info "配置文件已备份至: $backup_file"
}

# 更新配置并重启节点
update_config_and_restart() {
    local config_type="$1"  # 配置类型: "rpc_network", "rpc_auth", "other"
    local force_restart="$2"  # 是否强制重启: "true", "false", 默认根据配置类型决定
    
    # 检查节点是否在运行
    local is_running=false
    if pgrep bitcoind >/dev/null 2>&1; then
        is_running=true
    fi
    
    if [ "$is_running" = "false" ]; then
        log_info "节点未运行，配置将在下次启动时生效"
        return 0
    fi
    
    # 根据配置类型决定是否需要重启
    local needs_restart="unknown"
    case "$config_type" in
        "rpc_network")
            # RPC网络相关配置(rpcbind, rpcallowip)需要重启
            needs_restart="true"
            log_info "RPC网络配置已修改，需要重启节点以生效"
            ;;
        "rpc_auth")
            # RPC认证配置(rpcuser, rpcpassword)可能不需要重启
            # 但为了安全起见，建议重启
            needs_restart="optional"
            log_info "RPC认证配置已修改"
            ;;
        "other")
            # 其他配置
            needs_restart="true"
            log_info "配置已修改"
            ;;
    esac
    
    # 如果指定了强制重启，则覆盖默认行为
    if [ "$force_restart" = "true" ]; then
        needs_restart="true"
    elif [ "$force_restart" = "false" ]; then
        needs_restart="false"
    fi
    
    # 执行重启逻辑
    if [ "$needs_restart" = "true" ]; then
        log_info "重启节点以应用配置更改..."
        restart_bitcoin
    elif [ "$needs_restart" = "optional" ]; then
        echo ""
        log_warn "建议重启节点以确保配置完全生效"
        read -p "是否现在重启节点? (y/N): " confirm_restart
        if [[ $confirm_restart =~ ^[Yy]$ ]]; then
            log_info "重启节点..."
            restart_bitcoin
        else
            log_info "跳过重启，配置可能在下次重启后生效"
            log_info "如需立即应用所有更改，请手动执行: $0 restart"
        fi
    else
        log_info "配置无需重启即可生效"
    fi
}

# 设置允许的IP地址
set_allow_ip() {
    local ip_list="$1"
    
    if [ -z "$ip_list" ]; then
        log_error "请指定允许的IP地址"
        log_info "使用方法: $0 set-allow-ip <IP地址或CIDR>"
        log_info "示例: $0 set-allow-ip 192.168.1.0/24"
        log_info "示例: $0 set-allow-ip \"127.0.0.1,192.168.1.100\""
        return 1
    fi
    
    # 验证配置文件存在
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    backup_config
    
    # 分割IP列表并验证
    local valid_ips=""
    IFS=',' read -ra IP_ARRAY <<< "$ip_list"
    for ip in "${IP_ARRAY[@]}"; do
        ip=$(echo "$ip" | tr -d ' ')  # 去除空格
        if validate_ip "$ip"; then
            if [ -z "$valid_ips" ]; then
                valid_ips="$ip"
            else
                valid_ips="$valid_ips,$ip"
            fi
        else
            log_error "无效的IP地址格式: $ip"
            return 1
        fi
    done
    
    log_info "设置允许的IP地址: $valid_ips"
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        # 测试网：更新[test]节中的rpcallowip
        awk -v new_ips="$valid_ips" '
        /^\[test\]/{in_test=1}
        /^\[.*\]/ && !/^\[test\]/{in_test=0}
        in_test && /^rpcallowip=/{
            split(new_ips, ips, ",")
            for (i in ips) {
                print "rpcallowip=" ips[i]
            }
            next
        }
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    else
        # 主网：更新全局rpcallowip
        awk -v new_ips="$valid_ips" '
        /^rpcallowip=/ && !in_section {
            split(new_ips, ips, ",")
            for (i in ips) {
                print "rpcallowip=" ips[i]
            }
            next
        }
        /^\[.*\]/{in_section=1}
        /^$/{in_section=0}
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    fi
    
    mv "$temp_file" "$BITCOIN_CONF_FILE"
    
    log_info "IP访问控制列表已更新"
    update_config_and_restart "rpc_network" "$(get_restart_mode)"
}

# 绑定公网访问
bind_public() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    backup_config
    log_info "配置RPC绑定到公网 (0.0.0.0)..."
    
    local temp_file=$(mktemp)
    
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        # 测试网：更新[test]节
        awk '
        /^\[test\]/{in_test=1}
        /^\[.*\]/ && !/^\[test\]/{in_test=0}
        in_test && /^rpcbind=/{print "rpcbind=0.0.0.0"; next}
        in_test && /^rpcallowip=/ && /127\.0\.0\.1/{print "rpcallowip=0.0.0.0/0"; next}
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    else
        # 主网：更新全局配置
        awk '
        /^rpcbind=/ && !in_section {print "rpcbind=0.0.0.0"; next}
        /^rpcallowip=/ && !in_section && /127\.0\.0\.1/{print "rpcallowip=0.0.0.0/0"; next}
        /^\[.*\]/{in_section=1}
        /^$/{in_section=0}
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    fi
    
    mv "$temp_file" "$BITCOIN_CONF_FILE"
    
    log_info "RPC已绑定到公网 (0.0.0.0)"
    log_warn "⚠️  安全警告: RPC现在可以从任何IP访问，请确保："
    log_warn "   1. 防火墙已正确配置"
    log_warn "   2. 使用强密码"
    log_warn "   3. 考虑使用VPN或SSH隧道"
    
    update_config_and_restart "rpc_network" "$(get_restart_mode)"
}

# 绑定本地访问
bind_local() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    backup_config
    log_info "配置RPC绑定到本地 (127.0.0.1)..."
    
    local temp_file=$(mktemp)
    
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        # 测试网：更新[test]节
        awk '
        /^\[test\]/{in_test=1}
        /^\[.*\]/ && !/^\[test\]/{in_test=0}
        in_test && /^rpcbind=/{print "rpcbind=127.0.0.1"; next}
        in_test && /^rpcallowip=/ && /0\.0\.0\.0/{print "rpcallowip=127.0.0.1"; next}
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    else
        # 主网：更新全局配置
        awk '
        /^rpcbind=/ && !in_section {print "rpcbind=127.0.0.1"; next}
        /^rpcallowip=/ && !in_section && /0\.0\.0\.0/{print "rpcallowip=127.0.0.1"; next}
        /^\[.*\]/{in_section=1}
        /^$/{in_section=0}
        {print}
        ' "$BITCOIN_CONF_FILE" > "$temp_file"
    fi
    
    mv "$temp_file" "$BITCOIN_CONF_FILE"
    
    log_info "RPC已绑定到本地 (127.0.0.1)"
    log_info "✅ 安全提示: RPC现在仅允许本地访问"
    
    update_config_and_restart "rpc_network" "$(get_restart_mode)"
}

# 重置RPC密码
reset_password() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    backup_config
    
    # 生成新密码
    local new_password=""
    if command -v openssl >/dev/null 2>&1; then
        new_password=$(openssl rand -hex 32)
    else
        new_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    fi
    
    log_info "重置RPC密码..."
    
    local temp_file=$(mktemp)
    awk -v new_pass="$new_password" '
    /^rpcpassword=/{print "rpcpassword=" new_pass; next}
    {print}
    ' "$BITCOIN_CONF_FILE" > "$temp_file"
    
    mv "$temp_file" "$BITCOIN_CONF_FILE"
    
    log_info "RPC密码已重置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}新的RPC密码:${NC} ${YELLOW}$new_password${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请妥善保存此密码！"
    
    update_config_and_restart "rpc_auth" "$(get_restart_mode)"
}

# 移除RPC认证
remove_auth() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    log_warn "⚠️  危险操作: 这将移除RPC认证，任何人都可以访问你的节点"
    read -p "确定要移除RPC认证吗? (输入 'YES' 确认): " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        return 0
    fi
    
    backup_config
    log_info "移除RPC认证..."
    
    local temp_file=$(mktemp)
    awk '
    /^rpcuser=/{next}
    /^rpcpassword=/{next}
    {print}
    ' "$BITCOIN_CONF_FILE" > "$temp_file"
    
    mv "$temp_file" "$BITCOIN_CONF_FILE"
    
    log_info "RPC认证已移除"
    log_warn "⚠️  安全警告: RPC现在无需认证即可访问"
    log_warn "   强烈建议仅在受信任的环境中使用此配置"
    
    update_config_and_restart "rpc_auth" "$(get_restart_mode)"
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存 (至少需要2GB)
    case "$OS_FAMILY" in
        darwin)
            # macOS
            total_mem_bytes=$(sysctl -n hw.memsize)
            total_mem=$(echo "scale=1; $total_mem_bytes / 1024 / 1024 / 1024" | bc -l)
            ;;
        *)
            # Linux
            if command -v free >/dev/null 2>&1; then
                total_mem=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
            else
                # 备用方法
                total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
                total_mem=$(echo "scale=1; $total_mem_kb / 1024 / 1024" | bc -l)
            fi
            ;;
    esac
    
    if (( $(echo "$total_mem < 2.0" | bc -l) )); then
        log_error "系统内存不足: ${total_mem}GB (推荐至少2GB)"
        return 1
    fi
    log_info "内存检查通过: ${total_mem}GB"
    
    # 检查磁盘空间 - 根据修剪模式调整要求
    case "$OS_FAMILY" in
        darwin)
            # macOS
            available_space=$(df -g "$HOME" | awk 'NR==2 {print $4}')
            ;;
        *)
            # Linux
            available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
            ;;
    esac
    
    if [ "$PRUNE_MODE" = "true" ]; then
        # 修剪模式: 保留数据大小 + 30GB缓冲（相对保守）
        min_space=$((PRUNE_SIZE_GB + 30))
        log_info "修剪模式: 保留${PRUNE_SIZE_GB}GB区块数据，需要额外30GB缓冲空间"
    else
        # 完整模式
        if [ "$BITCOIN_NETWORK" = "testnet" ]; then
            min_space=80  # 测试网区块链较小，约50GB + 30GB缓冲
        else
            min_space=800  # 主网区块链约700GB+，预留更多空间
        fi
    fi
    
    if [ "$available_space" -lt "$min_space" ]; then
        log_error "磁盘空间不足: ${available_space}GB (${BITCOIN_NETWORK}网络${PRUNE_MODE:+修剪模式}推荐至少${min_space}GB)"
        return 1
    fi
    log_info "磁盘空间检查通过: ${available_space}GB"
    
    # 检查CPU核心数
    case "$OS_FAMILY" in
        darwin)
            cpu_cores=$(sysctl -n hw.ncpu)
            ;;
        *)
            cpu_cores=$(nproc)
            ;;
    esac
    
    if [ "$cpu_cores" -lt 2 ]; then
        log_warn "CPU核心数较少: ${cpu_cores}核心 (推荐至少2核心)"
    else
        log_info "CPU检查通过: ${cpu_cores}核心"
    fi
    
    return 0
}

# 安装Bitcoin节点
install_bitcoin() {
    log_info "开始安装Bitcoin节点 (网络: $BITCOIN_NETWORK, 系统: $OS_ID, 架构: $ARCH)"
    
    # 检查系统资源
    if ! check_system_resources; then
        log_error "系统资源检查失败，安装终止"
        exit 1
    fi
    
    # 检查是否已安装
    if command -v bitcoind >/dev/null 2>&1; then
        log_warn "Bitcoin Core已安装，版本: $(bitcoind --version | head -n1)"
        if [ "$FORCE_MODE" = "false" ]; then
            read -p "是否继续重新安装? (y/N): " confirm
            if [[ ! $confirm =~ ^[Yy]$ ]]; then
                exit 0
            fi
        else
            log_info "Force模式: 继续重新安装"
        fi
    fi
    
    # 更新系统包
    log_info "更新系统包并安装依赖..."
    check_dependencies
    
    # 根据系统和架构确定下载文件
    case "$OS_FAMILY" in
        darwin)
            if [ "$ARCH" = "aarch64" ]; then
                BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-arm64-apple-darwin.tar.gz"
            else
                BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-x86_64-apple-darwin.tar.gz"
            fi
            ;;
        *)
            # Linux
            case "$ARCH" in
                x86_64)
                    BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
                    ;;
                aarch64)
                    BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-aarch64-linux-gnu.tar.gz"
                    ;;
                arm)
                    BITCOIN_FILE="bitcoin-${BITCOIN_VERSION}-arm-linux-gnueabihf.tar.gz"
                    ;;
                *)
                    log_error "不支持的架构: $ARCH"
                    exit 1
                    ;;
            esac
            ;;
    esac
    
    # 下载Bitcoin Core
    log_info "下载Bitcoin Core v${BITCOIN_VERSION} ($BITCOIN_FILE)..."
    cd /tmp
    
    # 使用curl或wget下载
    if command -v curl >/dev/null 2>&1; then
        curl -fSL "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/${BITCOIN_FILE}" -o "${BITCOIN_FILE}"
        curl -fSL "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS" -o "SHA256SUMS"
    else
        wget -q "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/${BITCOIN_FILE}"
        wget -q "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
    fi
    
    # 验证下载文件
    log_info "验证下载文件..."
    if ! sha256sum -c --ignore-missing SHA256SUMS 2>/dev/null | grep -q "${BITCOIN_FILE}: OK"; then
        log_error "文件校验失败"
        exit 1
    fi
    
    # 解压并安装
    log_info "安装Bitcoin Core..."
    tar -xzf "${BITCOIN_FILE}"
    
    # 根据系统选择安装路径
    case "$OS_FAMILY" in
        darwin)
            # macOS: 复制到/usr/local/bin (需要sudo)
            if [ -w /usr/local/bin ]; then
                cp "bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
            else
                sudo cp "bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
            fi
            ;;
        *)
            # Linux: 复制到/usr/local/bin
            sudo cp "bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
            ;;
    esac
    
    # 创建数据目录
    mkdir -p "$BITCOIN_DATA_DIR"
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        mkdir -p "$BITCOIN_DATA_DIR/testnet3"
    fi
    
    # 生成RPC密码
    local rpc_password=""
    if command -v openssl >/dev/null 2>&1; then
        rpc_password=$(openssl rand -hex 32)
    else
        # 备用方法
        rpc_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    fi
    
    # 创建配置文件
    log_info "创建配置文件..."
    
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        # 测试网配置 - RPC相关配置都要放在[test]节中
        cat > "$BITCOIN_CONF_FILE" << EOF
# Bitcoin配置文件 - 网络: $BITCOIN_NETWORK
server=1
daemon=1
printtoconsole=0
rpcuser=bitcoinrpc
rpcpassword=$rpc_password
$( [ "$PRUNE_MODE" = "true" ] && echo "prune=$((PRUNE_SIZE_MB))" || echo "" )
disablewallet=1
dbcache=1000
maxconnections=50
testnet=1

[test]
rpcbind=127.0.0.1
rpcport=$DEFAULT_RPC_PORT
rpcallowip=127.0.0.1
EOF
    else
        # 主网配置
        cat > "$BITCOIN_CONF_FILE" << EOF
# Bitcoin配置文件 - 网络: $BITCOIN_NETWORK
server=1
daemon=1
printtoconsole=0
rpcuser=bitcoinrpc
rpcpassword=$rpc_password
rpcbind=127.0.0.1
rpcport=$DEFAULT_RPC_PORT
rpcallowip=127.0.0.1
$( [ "$PRUNE_MODE" = "true" ] && echo "prune=$((PRUNE_SIZE_MB))" || echo "" )
disablewallet=1
dbcache=1000
maxconnections=50
EOF
    fi
    
    # 创建服务文件
    create_service_file
    
    # 验证配置文件
    if ! validate_config; then
        log_error "配置文件验证失败，安装终止"
        exit 1
    fi
    
    # 清理临时文件
    rm -f "/tmp/${BITCOIN_FILE}"
    rm -f /tmp/SHA256SUMS
    rm -rf "/tmp/bitcoin-${BITCOIN_VERSION}"
    
    log_info "Bitcoin节点安装完成！"
    log_info "配置文件: $BITCOIN_CONF_FILE"
    log_info "数据目录: $BITCOIN_DATA_DIR"
    log_info "网络类型: $BITCOIN_NETWORK"
    if [ "$PRUNE_MODE" = "true" ]; then
        log_info "修剪模式: 启用 (保留${PRUNE_SIZE_GB}GB区块数据)"
    else
        log_info "修剪模式: 禁用 (保留完整区块链)"
    fi
    log_info "钱包功能: 禁用"
    log_info "RPC端口: $DEFAULT_RPC_PORT"
    log_info "RPC绑定: 127.0.0.1 (仅本地访问)"
    log_info "RPC访问控制: 127.0.0.1 (仅本地访问)"
    echo ""
    log_info "✅ 安全提示: 默认配置仅允许本地访问，这是最安全的配置"
    log_info "如需远程访问，请使用以下命令:"
    log_info "  - 绑定公网: $0 bind-public"
    log_info "  - 设置特定IP: $0 set-allow-ip <IP地址>"
    
    # 启动服务
    start_service
    
    # 等待一会儿再显示RPC信息
    sleep 3
    echo ""
    log_info "RPC连接信息将在节点启动后可用，使用以下命令查看:"
    echo "$0 rpc-url"
}

# 检查节点状态
check_status() {
    log_info "检查Bitcoin节点状态..."
    
    pid=$(pgrep bitcoind 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
        echo "bitcoind is running: $pid"
        
        # 显示更多状态信息
        if command -v bitcoin-cli >/dev/null 2>&1; then
            echo "节点信息:"
            bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getnetworkinfo 2>/dev/null | grep -E "(version|subversion|connections)" || echo "无法获取详细信息"
        fi
    else
        echo "bitcoind is not running"
    fi
    
    # 检查服务状态
    check_service_status
}

# 健康检查
health_check() {
    # 检查进程是否运行
    pid=$(pgrep bitcoind 2>/dev/null || echo "")
    if [ -z "$pid" ]; then
        echo "false"
        return 1
    fi
    
    # 检查RPC连接
    if ! command -v bitcoin-cli >/dev/null 2>&1; then
        echo "false"
        return 1
    fi
    
    # 尝试获取区块链信息
    if bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getblockchaininfo >/dev/null 2>&1; then
        # 检查是否正在同步
        sync_info=$(bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getblockchaininfo 2>/dev/null)
        if echo "$sync_info" | grep -q '"initialblockdownload": false'; then
            echo "true"
            return 0
        else
            # 仍在同步但节点运行正常
            echo "true"
            return 0
        fi
    else
        echo "false"
        return 1
    fi
}

# 重启节点
restart_bitcoin() {
    log_info "重启Bitcoin节点..."
    restart_service
    
    # 等待启动
    sleep 5
    
    if pgrep bitcoind >/dev/null 2>&1; then
        log_info "Bitcoin节点重启成功"
    else
        log_error "Bitcoin节点重启失败"
        exit 1
    fi
}

# 停止节点
stop_bitcoin() {
    log_info "停止Bitcoin节点..."
    
    # 首先尝试优雅停止
    if command -v bitcoin-cli >/dev/null 2>&1; then
        bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
        sleep 10
    fi
    
    # 使用服务管理器停止
    stop_service
    
    # 检查是否已停止
    pid=$(pgrep bitcoind 2>/dev/null || echo "")
    if [ -z "$pid" ]; then
        log_info "Bitcoin节点已停止"
    else
        log_warn "强制终止Bitcoin进程..."
        kill -9 "$pid" 2>/dev/null || sudo kill -9 "$pid" 2>/dev/null || true
        log_info "Bitcoin节点已强制停止"
    fi
}

# 卸载节点
uninstall_bitcoin() {
    log_warn "准备卸载Bitcoin节点..."
    if [ "$FORCE_MODE" = "false" ]; then
        read -p "这将删除所有Bitcoin相关文件，是否继续? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_info "Force模式: 强制卸载Bitcoin节点"
    fi
    
    # 停止服务
    log_info "停止Bitcoin服务..."
    stop_service
    
    # 删除服务文件
    log_info "删除服务文件..."
    case "$SERVICE_MANAGER" in
        systemd)
            sudo systemctl disable bitcoind 2>/dev/null || true
            sudo rm -f /etc/systemd/system/bitcoind.service
            sudo systemctl daemon-reload
            ;;
        launchd)
            launchctl unload "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist" 2>/dev/null || true
            rm -f "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist"
            ;;
    esac
    
    # 删除二进制文件
    log_info "删除Bitcoin二进制文件..."
    case "$OS_FAMILY" in
        darwin)
            rm -f /usr/local/bin/bitcoin* 2>/dev/null || sudo rm -f /usr/local/bin/bitcoin* 2>/dev/null || true
            ;;
        *)
            sudo rm -f /usr/local/bin/bitcoin*
            ;;
    esac
    
    # 询问是否删除数据目录
    if [ "$FORCE_MODE" = "false" ]; then
        read -p "是否删除数据目录 $BITCOIN_DATA_DIR? (y/N): " confirm_data
        if [[ $confirm_data =~ ^[Yy]$ ]]; then
            log_info "删除数据目录..."
            rm -rf "$BITCOIN_DATA_DIR"
        else
            log_info "保留数据目录: $BITCOIN_DATA_DIR"
        fi
    else
        log_info "Force模式: 删除数据目录 $BITCOIN_DATA_DIR"
        rm -rf "$BITCOIN_DATA_DIR"
    fi
    
    log_info "Bitcoin节点卸载完成"
}

# 查看日志
view_logs() {
    log_info "显示最近100条日志..."
    
    # 根据实际配置文件确定日志文件路径
    local actual_network=$(detect_actual_network)
    local log_file=""
    
    if [ "$actual_network" = "testnet" ]; then
        log_file="$BITCOIN_DATA_DIR/testnet3/debug.log"
    else
        log_file="$BITCOIN_DATA_DIR/debug.log"
    fi
    
    if [ -f "$log_file" ]; then
        log_info "显示日志文件: $log_file"
        tail -n 100 "$log_file"
    else
        log_warn "日志文件不存在: $log_file"
        
        # 如果实际网络类型与脚本参数不同，尝试另一个路径
        local fallback_log=""
        if [ "$actual_network" = "testnet" ]; then
            fallback_log="$BITCOIN_DATA_DIR/debug.log"
        else
            fallback_log="$BITCOIN_DATA_DIR/testnet3/debug.log"
        fi
        
        if [ -f "$fallback_log" ]; then
            log_info "尝试备用日志文件: $fallback_log"
            tail -n 100 "$fallback_log"
        else
            # 尝试显示systemd日志
            log_info "显示systemd日志..."
            sudo journalctl -u bitcoind -n 100 --no-pager 2>/dev/null || {
                log_error "无法找到任何日志文件"
                log_info "可能的日志位置:"
                log_info "  主网: $BITCOIN_DATA_DIR/debug.log"
                log_info "  测试网: $BITCOIN_DATA_DIR/testnet3/debug.log"
                return 1
            }
        fi
    fi
}

# 查看同步进度并预计同步完成时间
sync_progress() {
    if ! command -v bitcoin-cli >/dev/null 2>&1; then
        log_error "未找到 bitcoin-cli 命令，请确认是否已安装 Bitcoin Core"
        exit 1
    fi

    if ! bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getblockchaininfo >/dev/null 2>&1; then
        log_error "无法连接 Bitcoin 节点，请确认节点是否已启动"
        exit 1
    fi

    local info=$(bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" getblockchaininfo)
    local progress=$(echo "$info" | jq -r '.verificationprogress // 0')
    local blocks=$(echo "$info" | jq -r '.blocks // 0')
    local headers=$(echo "$info" | jq -r '.headers // 0')
    local initial_download=$(echo "$info" | jq -r '.initialblockdownload // true')
    local size_on_disk=$(echo "$info" | jq -r '.size_on_disk // 0')
    local pruned=$(echo "$info" | jq -r '.pruned // false')

    # 计算百分比
    local percent=$(echo "$progress * 100" | bc -l 2>/dev/null || echo "0")
    percent=$(printf "%.6f" "$percent" 2>/dev/null || echo "0.000000")
    
    echo -e "${GREEN}同步进度：${percent}%（当前高度：$blocks / 区块头：$headers）${NC}"
    
    # 显示磁盘使用情况
    if [ "$size_on_disk" != "0" ]; then
        local size_gb=$(echo "scale=2; $size_on_disk / (1024*1024*1024)" | bc -l 2>/dev/null || echo "计算失败")
        echo -e "${GREEN}磁盘使用：${size_gb}GB${NC}"
    fi
    
    # 显示修剪状态
    if [ "$pruned" = "true" ]; then
        echo -e "${YELLOW}修剪模式：已启用${NC}"
    else
        echo -e "${GREEN}修剪模式：未启用（保留完整区块链）${NC}"
    fi
    
    if [ "$initial_download" = "false" ]; then
        echo -e "${GREEN}节点已同步完成。${NC}"
        return 0
    fi

    # 初期阶段提示
    if [ "$blocks" -lt 100000 ]; then
        echo -e "${YELLOW}同步刚开始，当前区块高度还低（<10万），这是最慢阶段，请耐心等待。${NC}"
        if [ "$pruned" = "true" ]; then
            echo -e "${YELLOW}修剪模式下预计同步时间：1～3天（视网络带宽和磁盘性能而定）${NC}"
        else
            echo -e "${YELLOW}完整模式下预计同步时间：3～7天（视网络带宽和磁盘性能而定）${NC}"
        fi
        return 0
    fi

    # 记录上次进度文件
    local tmp_file="/tmp/.bitcoin_sync_progress_${BITCOIN_NETWORK}"
    local now_ts=$(date +%s)

    if [ -f "$tmp_file" ]; then
        local last_line=$(tail -n1 "$tmp_file" 2>/dev/null || echo "")
        if [ -n "$last_line" ]; then
            local last_ts=$(echo "$last_line" | cut -d',' -f1)
            local last_progress=$(echo "$last_line" | cut -d',' -f2)
            local last_blocks=$(echo "$last_line" | cut -d',' -f3)

            local delta_time=$((now_ts - last_ts))
            
            # 使用 bc 计算浮点数差值
            if [ "$delta_time" -gt 60 ] && command -v bc >/dev/null 2>&1; then
                local delta_progress=$(echo "$progress - $last_progress" | bc -l 2>/dev/null || echo "0")
                
                # 检查是否有进展
                if (( $(echo "$delta_progress > 0" | bc -l 2>/dev/null || echo "0") )); then
                    local speed=$(echo "$delta_progress / $delta_time" | bc -l 2>/dev/null || echo "0")
                    local remaining_progress=$(echo "1 - $progress" | bc -l 2>/dev/null || echo "1")
                    local remaining_seconds=$(echo "$remaining_progress / $speed" | bc -l 2>/dev/null || echo "0")
                    
                    # 转换为可读时间
                    if (( $(echo "$remaining_seconds > 0" | bc -l 2>/dev/null || echo "0") )); then
                        local hours=$(echo "$remaining_seconds / 3600" | bc -l 2>/dev/null || echo "0")
                        local days=$(echo "$hours / 24" | bc -l 2>/dev/null || echo "0")
                        
                        hours=$(printf "%.1f" "$hours" 2>/dev/null || echo "0.0")
                        days=$(printf "%.1f" "$days" 2>/dev/null || echo "0.0")
                        
                        echo -e "${YELLOW}基于最近进展预估剩余时间：约 ${hours} 小时（${days} 天）${NC}"
                        
                        # 计算预计完成时间，显示本地时区
                        local remaining_seconds_int=$(echo "$remaining_seconds" | cut -d'.' -f1)
                        if [ -n "$remaining_seconds_int" ] && [ "$remaining_seconds_int" -gt 0 ] 2>/dev/null; then
                            local eta_timestamp=$((now_ts + remaining_seconds_int))
                            local eta_local=$(date -d "@$eta_timestamp" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "计算失败")
                        else
                            local eta_local="计算失败"
                        fi
                        local timezone=$(date "+%Z %z" 2>/dev/null || echo "")
                        echo -e "${YELLOW}预计完成时间：$eta_local${NC}"
                        if [ -n "$timezone" ]; then
                            echo -e "${YELLOW}当前时区：$timezone${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}同步速度较慢，请检查网络连接和磁盘性能${NC}"
                fi
            fi
        fi
    fi

    # 记录当前状态
    echo "$now_ts,$progress,$blocks" >> "$tmp_file"
    
    # 保持文件大小，只保留最近10条记录
    if [ -f "$tmp_file" ]; then
        tail -n 10 "$tmp_file" > "${tmp_file}.tmp" && mv "${tmp_file}.tmp" "$tmp_file"
    fi
}

# 创建服务文件
create_service_file() {
    case "$SERVICE_MANAGER" in
        systemd)
            log_info "创建systemd服务..."
            sudo tee /etc/systemd/system/bitcoind.service > /dev/null << EOF
[Unit]
Description=Bitcoin daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/bitcoind -conf=$BITCOIN_CONF_FILE -datadir=$BITCOIN_DATA_DIR
ExecStop=/usr/local/bin/bitcoin-cli -conf=$BITCOIN_CONF_FILE -datadir=$BITCOIN_DATA_DIR stop
ExecReload=/bin/kill -HUP \$MAINPID
User=$BITCOIN_USER
Type=forking
PIDFile=$BITCOIN_PID_FILE
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable bitcoind
            ;;
        launchd)
            # macOS launchd服务
            log_info "创建launchd服务..."
            local plist_file="$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist"
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.bitcoin.bitcoind</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bitcoind</string>
        <string>-conf=$BITCOIN_CONF_FILE</string>
        <string>-datadir=$BITCOIN_DATA_DIR</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$BITCOIN_DATA_DIR/bitcoind.out</string>
    <key>StandardErrorPath</key>
    <string>$BITCOIN_DATA_DIR/bitcoind.err</string>
</dict>
</plist>
EOF
            ;;
        *)
            log_warn "不支持的服务管理器，请手动启动bitcoind"
            ;;
    esac
}

# 启动服务
start_service() {
    case "$SERVICE_MANAGER" in
        systemd)
            log_info "启动systemd服务..."
            sudo systemctl start bitcoind
            ;;
        launchd)
            log_info "启动launchd服务..."
            launchctl load "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist"
            ;;
        *)
            log_info "手动启动bitcoind..."
            nohup bitcoind -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" > "$BITCOIN_DATA_DIR/bitcoind.out" 2>&1 &
            ;;
    esac
}

# 停止服务
stop_service() {
    case "$SERVICE_MANAGER" in
        systemd)
            sudo systemctl stop bitcoind
            ;;
        launchd)
            launchctl unload "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist" 2>/dev/null || true
            ;;
        *)
            # 手动停止
            if command -v bitcoin-cli >/dev/null 2>&1; then
                bitcoin-cli -conf="$BITCOIN_CONF_FILE" -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
            fi
            sleep 5
            pkill bitcoind 2>/dev/null || true
            ;;
    esac
}

# 重启服务
restart_service() {
    case "$SERVICE_MANAGER" in
        systemd)
            sudo systemctl restart bitcoind
            ;;
        launchd)
            launchctl unload "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist" 2>/dev/null || true
            sleep 2
            launchctl load "$HOME/Library/LaunchAgents/com.bitcoin.bitcoind.plist"
            ;;
        *)
            stop_service
            sleep 5
            start_service
            ;;
    esac
}

# 检查服务状态
check_service_status() {
    case "$SERVICE_MANAGER" in
        systemd)
            if systemctl is-active --quiet bitcoind; then
                echo "systemd服务状态: active"
            else
                echo "systemd服务状态: inactive"
            fi
            ;;
        launchd)
            if launchctl list | grep -q com.bitcoin.bitcoind; then
                echo "launchd服务状态: loaded"
            else
                echo "launchd服务状态: not loaded"
            fi
            ;;
        *)
            echo "服务管理器: 手动模式"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    echo "Bitcoin节点管理脚本"
    echo ""
    echo "用法: $0 [--force] [--prune] [命令] [网络类型]"
    echo ""
    echo "选项:"
    echo "  --force   - 强制模式，跳过所有确认提示"
    echo "  --prune   - 启用修剪模式，限制数据目录大小"
    echo "  --force-restart - 强制重启节点"
    echo "  --skip-restart - 跳过重启节点"
    echo ""
    echo "命令:"
    echo "  install        - 安装Bitcoin节点"
    echo "  status         - 检查节点状态"
    echo "  health         - 健康检查"
    echo "  restart        - 重启节点"
    echo "  stop           - 停止节点"
    echo "  uninstall      - 卸载节点"
    echo "  logs           - 查看最近100条日志"
    echo "  sync           - 查看同步进度"
    echo "  rpc-url        - 显示RPC连接信息和完整URL"
    echo ""
    echo "RPC管理命令:"
    echo "  set-allow-ip <IP地址>  - 设置允许访问的IP地址"
    echo "  bind-public            - 绑定公网访问 (0.0.0.0)"
    echo "  bind-local             - 绑定本地访问 (127.0.0.1)"
    echo "  reset-password         - 重置RPC密码"
    echo "  remove-auth            - 移除RPC认证 (危险)"
    echo ""
    echo "环境变量:"
    echo "  BITCOIN_NETWORK   - 网络类型 (mainnet|testnet, 默认: mainnet)"
    echo "  BITCOIN_DATA_DIR  - 数据目录 (默认: ~/.bitcoin)"
    echo "  BITCOIN_USER      - 运行用户 (默认: 当前用户)"
    echo "  BITCOIN_PRUNE     - 修剪模式 (默认: false)"
    echo "  PRUNE_SIZE_GB     - 修剪保留大小GB (主网默认: 50GB, 测试网默认: 20GB)"
    echo ""
    echo "修剪模式说明:"
    echo "  主网: 修剪大小不能超过800GB，否则建议使用全节点"
    echo "  测试网: 修剪大小不能超过80GB，否则建议使用全节点"
    echo ""
    echo "示例:"
    echo "  $0 install"
    echo "  $0 --force install"
    echo "  $0 --prune install"
    echo "  $0 --force --prune install"
    echo "  BITCOIN_NETWORK=testnet $0 --force install"
    echo "  BITCOIN_NETWORK=testnet PRUNE_SIZE_GB=30 $0 --prune install"
    echo "  PRUNE_SIZE_GB=30 $0 --prune install  # 主网30GB修剪模式"
    echo "  PRUNE_SIZE_GB=15 $0 --prune install testnet  # 测试网15GB修剪模式"
    echo "  $0 status"
    echo "  $0 health"
    echo "  $0 sync"
    echo "  $0 rpc-url"
    echo ""
    echo "RPC管理示例:"
    echo "  $0 set-allow-ip 192.168.1.0/24        # 允许局域网访问"
    echo "  $0 set-allow-ip \"127.0.0.1,10.0.0.5\"  # 允许多个IP"
    echo "  $0 bind-public                         # 绑定公网访问"
    echo "  $0 bind-local                          # 绑定本地访问"
    echo "  $0 reset-password                      # 重置RPC密码"
    echo "  $0 remove-auth                         # 移除认证(危险)"
    echo ""
    echo "重启控制示例:"
    echo "  $0 --force-restart bind-public         # 绑定公网并强制重启"
    echo "  $0 --skip-restart reset-password       # 重置密码但跳过重启"
    echo "  $0 --skip-restart set-allow-ip 10.0.0.1 # 设置IP但跳过重启"
    echo ""
    echo "获取RPC URL用于脚本调用:"
    echo "  RPC_URL=\$($0 rpc-url --url-only)"
    echo ""
    echo "安全建议:"
    echo "  • 默认配置仅允许本地访问 (127.0.0.1)"
    echo "  • 使用 bind-public 前请确保防火墙已配置"
    echo "  • 定期使用 reset-password 更换密码"
    echo "  • 避免在生产环境使用 remove-auth"
}

# 获取公网IP地址
get_public_ip() {
    local public_ip=""
    
    # 尝试多个服务获取公网IP
    local ip_services=(
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
        "https://ipecho.net/plain"
        "https://ident.me"
    )
    
    for service in "${ip_services[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            public_ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '\n\r' | head -c 15)
        elif command -v wget >/dev/null 2>&1; then
            public_ip=$(wget -qO- --timeout=10 "$service" 2>/dev/null | tr -d '\n\r' | head -c 15)
        fi
        
        # 验证IP格式
        if [[ $public_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$public_ip"
            return 0
        fi
    done
    
    # 如果都失败了，返回空
    echo ""
    return 1
}

# 获取本地IP地址
get_local_ip() {
    local local_ip=""
    
    case "$OS_FAMILY" in
        darwin)
            # macOS
            local_ip=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | head -n1 | awk '{print $2}')
            ;;
        *)
            # Linux
            local_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -n1)
            if [ -z "$local_ip" ]; then
                # 备用方法
                local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            fi
            ;;
    esac
    
    echo "$local_ip"
}

# 验证配置文件
validate_config() {
    log_info "验证配置文件..."
    
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi
    
    # 检查基本配置
    if ! grep -q "^rpcuser=" "$BITCOIN_CONF_FILE"; then
        log_error "配置文件缺少rpcuser配置"
        return 1
    fi
    
    if ! grep -q "^rpcpassword=" "$BITCOIN_CONF_FILE"; then
        log_error "配置文件缺少rpcpassword配置"
        return 1
    fi
    
    # 检查网络特定配置
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        if ! grep -q "^testnet=1" "$BITCOIN_CONF_FILE"; then
            log_error "测试网配置缺少testnet=1"
            return 1
        fi
        
        if ! grep -A 10 "^\[test\]" "$BITCOIN_CONF_FILE" | grep -q "^rpcbind="; then
            log_error "测试网配置缺少[test]节中的rpcbind设置"
            return 1
        fi
        
        if ! grep -A 10 "^\[test\]" "$BITCOIN_CONF_FILE" | grep -q "^rpcport="; then
            log_error "测试网配置缺少[test]节中的rpcport设置"
            return 1
        fi
        
        log_info "测试网配置验证通过"
    else
        if ! grep -q "^rpcbind=" "$BITCOIN_CONF_FILE"; then
            log_error "主网配置缺少rpcbind设置"
            return 1
        fi
        
        if ! grep -q "^rpcport=" "$BITCOIN_CONF_FILE"; then
            log_error "主网配置缺少rpcport设置"
            return 1
        fi
        
        log_info "主网配置验证通过"
    fi
    
    return 0
}

# 主程序
main() {
    # 处理命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --prune)
                PRUNE_MODE=true
                shift
                ;;
            --force-restart)
                FORCE_RESTART=true
                shift
                ;;
            --skip-restart)
                SKIP_RESTART=true
                shift
                ;;
            --url-only)
                URL_ONLY=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 检查参数
    if [ $# -lt 1 ]; then
        show_help
        exit 1
    fi
    
    COMMAND="$1"
    
    # 处理网络类型参数
    if [ $# -eq 2 ]; then
        BITCOIN_NETWORK="$2"
    fi
    
    # 验证网络类型
    if [[ "$BITCOIN_NETWORK" != "mainnet" && "$BITCOIN_NETWORK" != "testnet" ]]; then
        log_error "无效的网络类型: $BITCOIN_NETWORK (支持: mainnet, testnet)"
        exit 1
    fi
    
    # 重新设置路径（根据网络类型）
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/testnet3/debug.log"
        BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/testnet3/bitcoind.pid"
        DEFAULT_RPC_PORT="18332"
    else
        DEFAULT_RPC_PORT="8332"
    fi
    
    case "$COMMAND" in
        install)
            install_bitcoin
            ;;
        status)
            check_status
            ;;
        health)
            health_check
            ;;
        restart)
            restart_bitcoin
            ;;
        stop)
            stop_bitcoin
            ;;
        uninstall)
            uninstall_bitcoin
            ;;
        logs)
            view_logs
            ;;
        sync)
            sync_progress
            ;;
        rpc-url)
            if [ "$URL_ONLY" = "true" ]; then
                get_rpc_url_only
            else
                show_rpc_url
            fi
            ;;
        set-allow-ip)
            shift  # 移除命令参数
            if [ $# -ge 1 ]; then
                set_allow_ip "$1"
            else
                log_error "请提供有效的IP地址或CIDR"
                log_info "使用方法: $0 set-allow-ip <IP地址或CIDR>"
                exit 1
            fi
            ;;
        bind-public)
            bind_public
            ;;
        bind-local)
            bind_local
            ;;
        reset-password)
            reset_password
            ;;
        remove-auth)
            remove_auth
            ;;
        *)
            log_error "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@"
