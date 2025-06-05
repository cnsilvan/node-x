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

# 默认配置
BITCOIN_NETWORK=${BITCOIN_NETWORK:-"mainnet"}
BITCOIN_USER=${BITCOIN_USER:-$(whoami)}
BITCOIN_DATA_DIR=${BITCOIN_DATA_DIR:-"$HOME/.bitcoin"}
BITCOIN_VERSION="28.1"
BITCOIN_SERVICE_NAME="bitcoind"
FORCE_MODE=false
PRUNE_MODE=false

# 修剪模式配置 (GB)
PRUNE_SIZE_GB=${PRUNE_SIZE_GB:-50}  # 默认保留50GB区块数据

# 系统相关变量 (将在detect_os()中设置)
OS_ID=""
OS_FAMILY=""
PACKAGE_MANAGER=""
SERVICE_MANAGER=""
ARCH=""

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
else
    BITCOIN_CONF_FILE="$BITCOIN_DATA_DIR/bitcoin.conf"
    BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/debug.log"
    BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/bitcoind.pid"
    DEFAULT_RPC_PORT="8332"
fi

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

# 获取RPC连接信息
get_rpc_info() {
    if [ ! -f "$BITCOIN_CONF_FILE" ]; then
        log_error "配置文件不存在: $BITCOIN_CONF_FILE"
        return 1
    fi

    # 从配置文件读取RPC信息
    local rpc_user=$(grep "^rpcuser=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    local rpc_password=$(grep "^rpcpassword=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
    local rpc_port=$(grep "^rpcport=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 || echo "$DEFAULT_RPC_PORT")
    local rpc_bind=$(grep "^rpcbind=" "$BITCOIN_CONF_FILE" 2>/dev/null | cut -d'=' -f2 | head -n1 || echo "127.0.0.1")

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

    # 构建完整的RPC URL
    local rpc_url="http://${rpc_user}:${rpc_password}@${rpc_host}:${rpc_port}/"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}Bitcoin节点RPC连接信息${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}网络类型:${NC} $BITCOIN_NETWORK"
    echo -e "${YELLOW}RPC主机:${NC} $rpc_host"
    echo -e "${YELLOW}RPC端口:${NC} $rpc_port"
    echo -e "${YELLOW}RPC用户:${NC} $rpc_user"
    echo -e "${YELLOW}RPC密码:${NC} $rpc_password"
    
    # 显示配置模式信息
    if grep -q "^prune=" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        local prune_size=$(grep "^prune=" "$BITCOIN_CONF_FILE" | cut -d'=' -f2)
        local prune_gb=$((prune_size / 1000))
        echo -e "${YELLOW}修剪模式:${NC} 启用 (保留${prune_gb}GB区块数据)"
    else
        echo -e "${YELLOW}修剪模式:${NC} 禁用 (保留完整区块链)"
    fi
    
    if grep -q "^disablewallet=1" "$BITCOIN_CONF_FILE" 2>/dev/null; then
        echo -e "${YELLOW}钱包功能:${NC} 禁用"
    else
        echo -e "${YELLOW}钱包功能:${NC} 启用"
    fi
    
    echo ""
    echo -e "${GREEN}完整RPC URL:${NC}"
    echo -e "${YELLOW}$rpc_url${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${GREEN}使用示例:${NC}"
    echo ""
    echo -e "${YELLOW}curl命令示例:${NC}"
    echo "curl -u \"$rpc_user:$rpc_password\" -d '{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'content-type: text/plain;' http://$rpc_host:$rpc_port/"
    echo ""
    echo -e "${YELLOW}Python示例:${NC}"
    echo "import requests"
    echo "rpc_url = '$rpc_url'"
    echo "payload = {\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}"
    echo "response = requests.post(rpc_url, json=payload)"
    echo "print(response.json())"
    echo ""
    echo -e "${YELLOW}Node.js示例:${NC}"
    echo "const axios = require('axios');"
    echo "const rpcUrl = '$rpc_url';"
    echo "const payload = {jsonrpc:'1.0',id:'test',method:'getblockchaininfo',params:[]};"
    echo "axios.post(rpcUrl, payload).then(res => console.log(res.data));"
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
    
    # 安全提醒
    echo -e "${RED}⚠️  安全提醒:${NC}"
    echo "• RPC密码包含敏感信息，请勿在不安全的环境中分享"
    echo "• 默认情况下，RPC服务只绑定到本地地址 (127.0.0.1)"
    echo "• 如需远程访问，请配置防火墙和安全策略"
    echo "• 建议定期更换RPC密码"
    echo ""
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

    echo "http://${rpc_user}:${rpc_password}@${rpc_host}:${rpc_port}/"
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
        # 修剪模式: 保留数据大小 + 50GB缓冲
        min_space=$((PRUNE_SIZE_GB + 50))
        log_info "修剪模式: 保留${PRUNE_SIZE_GB}GB区块数据"
    else
        # 完整模式
        if [ "$BITCOIN_NETWORK" = "testnet" ]; then
            min_space=80
        else
            min_space=800
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
    cat > "$BITCOIN_CONF_FILE" << EOF
# Bitcoin配置文件 - 网络: $BITCOIN_NETWORK
server=1
daemon=1
printtoconsole=0
rpcuser=bitcoinrpc
rpcpassword=$rpc_password
rpcbind=127.0.0.1
rpcport=$DEFAULT_RPC_PORT
$( [ "$BITCOIN_NETWORK" = "testnet" ] && echo "testnet=1" || echo "" )
$( [ "$PRUNE_MODE" = "true" ] && echo "prune=$((PRUNE_SIZE_GB * 1000))" || echo "" )
disablewallet=1
dbcache=1000
maxconnections=50
EOF
    
    # 创建服务文件
    create_service_file
    
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
        log_info "Force模式: 保留数据目录 $BITCOIN_DATA_DIR"
    fi
    
    log_info "Bitcoin节点卸载完成"
}

# 查看日志
view_logs() {
    log_info "显示最近100条日志..."
    
    if [ -f "$BITCOIN_LOG_FILE" ]; then
        tail -n 100 "$BITCOIN_LOG_FILE"
    else
        log_warn "日志文件不存在: $BITCOIN_LOG_FILE"
        
        # 尝试显示systemd日志
        log_info "显示systemd日志..."
        sudo journalctl -u bitcoind -n 100 --no-pager
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
                        local eta_timestamp=$((now_ts + $(echo "$remaining_seconds" | cut -d'.' -f1)))
                        local eta_local=$(date -d "@$eta_timestamp" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "计算失败")
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
    echo ""
    echo "命令:"
    echo "  install   - 安装Bitcoin节点"
    echo "  status    - 检查节点状态"
    echo "  health    - 健康检查"
    echo "  restart   - 重启节点"
    echo "  stop      - 停止节点"
    echo "  uninstall - 卸载节点"
    echo "  logs      - 查看最近100条日志"
    echo "  sync      - 查看同步进度"
    echo "  rpc-url   - 显示RPC连接信息和完整URL"
    echo ""
    echo "环境变量:"
    echo "  BITCOIN_NETWORK   - 网络类型 (mainnet|testnet, 默认: mainnet)"
    echo "  BITCOIN_DATA_DIR  - 数据目录 (默认: ~/.bitcoin)"
    echo "  BITCOIN_USER      - 运行用户 (默认: 当前用户)"
    echo "  BITCOIN_PRUNE     - 修剪模式 (默认: false)"
    echo ""
    echo "示例:"
    echo "  $0 install"
    echo "  $0 --force install"
    echo "  $0 --prune install"
    echo "  $0 --force --prune install"
    echo "  BITCOIN_NETWORK=testnet $0 --force install"
    echo "  BITCOIN_NETWORK=testnet PRUNE_SIZE_GB=30 $0 --prune install"
    echo "  $0 status"
    echo "  $0 health"
    echo "  $0 sync"
    echo "  $0 rpc-url"
    echo ""
    echo "获取RPC URL用于脚本调用:"
    echo "  RPC_URL=\$($0 rpc-url --url-only)"
    echo ""
    echo "nohup使用示例:"
    echo "  nohup $0 --force install > install.log 2>&1 &"
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
        *)
            log_error "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@"
