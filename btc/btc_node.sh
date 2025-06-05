#!/bin/bash

# Bitcoin节点管理脚本
# 使用方法: ./bitcoin_node.sh [--force] [install|status|health|restart|stop|uninstall|logs] [mainnet|testnet]
# 环境变量:
# BITCOIN_NETWORK: mainnet 或 testnet (默认: mainnet)
# BITCOIN_DATA_DIR: 数据目录 (默认: ~/.bitcoin)
# BITCOIN_USER: 运行用户 (默认: 当前用户)

set -e

# 默认配置
BITCOIN_NETWORK=${BITCOIN_NETWORK:-"mainnet"}
BITCOIN_USER=${BITCOIN_USER:-$(whoami)}
BITCOIN_DATA_DIR=${BITCOIN_DATA_DIR:-"$HOME/.bitcoin"}
BITCOIN_VERSION="28.1"
BITCOIN_SERVICE_NAME="bitcoind"
FORCE_MODE=false

# 根据网络类型设置配置
if [ "$BITCOIN_NETWORK" = "testnet" ]; then
    BITCOIN_CONF_FILE="$BITCOIN_DATA_DIR/bitcoin.conf"
    BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/testnet3/debug.log"
    BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/testnet3/bitcoind.pid"
else
    BITCOIN_CONF_FILE="$BITCOIN_DATA_DIR/bitcoin.conf"
    BITCOIN_LOG_FILE="$BITCOIN_DATA_DIR/debug.log"
    BITCOIN_PID_FILE="$BITCOIN_DATA_DIR/bitcoind.pid"
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

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存 (至少需要2GB)
    total_mem=$(free -m | awk 'NR==2{printf "%.1f", $2/1024}')
    if (( $(echo "$total_mem < 2.0" | bc -l) )); then
        log_error "系统内存不足: ${total_mem}GB (推荐至少2GB)"
        return 1
    fi
    log_info "内存检查通过: ${total_mem}GB"
    
    # 检查磁盘空间 (主网至少需要800GB，测试网至少需要80GB)
    available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        min_space=80
    else
        min_space=800
    fi
    
    if [ "$available_space" -lt "$min_space" ]; then
        log_error "磁盘空间不足: ${available_space}GB (${BITCOIN_NETWORK}网络推荐至少${min_space}GB)"
        return 1
    fi
    log_info "磁盘空间检查通过: ${available_space}GB"
    
    # 检查CPU核心数
    cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log_warn "CPU核心数较少: ${cpu_cores}核心 (推荐至少2核心)"
    else
        log_info "CPU检查通过: ${cpu_cores}核心"
    fi
    
    return 0
}

# 安装Bitcoin节点
install_bitcoin() {
    log_info "开始安装Bitcoin节点 (网络: $BITCOIN_NETWORK)"
    
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
    log_info "更新系统包..."
    sudo apt update
    sudo apt install -y wget curl bc
    
    # 下载Bitcoin Core
    log_info "下载Bitcoin Core v${BITCOIN_VERSION}..."
    cd /tmp
    wget -q "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
    wget -q "https://bitcoin.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
    
    # 验证下载文件
    log_info "验证下载文件..."
    if ! sha256sum -c --ignore-missing SHA256SUMS 2>/dev/null | grep -q "bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz: OK"; then
        log_error "文件校验失败"
        exit 1
    fi
    
    # 解压并安装
    log_info "安装Bitcoin Core..."
    tar -xzf "bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
    sudo cp "bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
    
    # 创建数据目录
    mkdir -p "$BITCOIN_DATA_DIR"
    if [ "$BITCOIN_NETWORK" = "testnet" ]; then
        mkdir -p "$BITCOIN_DATA_DIR/testnet3"
    fi
    
    # 创建配置文件
    log_info "创建配置文件..."
    cat > "$BITCOIN_CONF_FILE" << EOF
# Bitcoin配置文件 - 网络: $BITCOIN_NETWORK
server=1
daemon=1
printtoconsole=0
rpcuser=bitcoinrpc
rpcpassword=$(openssl rand -hex 32)
rpcbind=127.0.0.1
rpcport=$( [ "$BITCOIN_NETWORK" = "testnet" ] && echo "18332" || echo "8332" )
$( [ "$BITCOIN_NETWORK" = "testnet" ] && echo "testnet=1" || echo "" )
dbcache=1000
maxconnections=50
EOF
    
    # 创建systemd服务
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
    
    # 清理临时文件
    rm -f /tmp/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz
    rm -f /tmp/SHA256SUMS
    rm -rf "/tmp/bitcoin-${BITCOIN_VERSION}"
    
    log_info "Bitcoin节点安装完成！"
    log_info "配置文件: $BITCOIN_CONF_FILE"
    log_info "数据目录: $BITCOIN_DATA_DIR"
    log_info "使用 'sudo systemctl start bitcoind' 启动服务"
}

# 检查节点状态
check_status() {
    log_info "检查Bitcoin节点状态..."
    
    pid=$(pgrep bitcoind)
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
    
    # 检查systemd服务状态
    if systemctl is-active --quiet bitcoind; then
        echo "systemd服务状态: active"
    else
        echo "systemd服务状态: inactive"
    fi
}

# 健康检查
health_check() {
    # 检查进程是否运行
    pid=$(pgrep bitcoind)
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
    sudo systemctl restart bitcoind
    
    # 等待启动
    sleep 5
    
    if systemctl is-active --quiet bitcoind; then
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
    
    # 使用systemd停止
    sudo systemctl stop bitcoind
    
    # 检查是否已停止
    pid=$(pgrep bitcoind)
    if [ -z "$pid" ]; then
        log_info "Bitcoin节点已停止"
    else
        log_warn "强制终止Bitcoin进程..."
        sudo kill -9 "$pid"
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
    sudo systemctl stop bitcoind 2>/dev/null || true
    sudo systemctl disable bitcoind 2>/dev/null || true
    
    # 删除systemd服务文件
    log_info "删除systemd服务..."
    sudo rm -f /etc/systemd/system/bitcoind.service
    sudo systemctl daemon-reload
    
    # 删除二进制文件
    log_info "删除Bitcoin二进制文件..."
    sudo rm -f /usr/local/bin/bitcoin*
    
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
    local progress=$(echo "$info" | grep -o '"verificationprogress":[0-9.]*' | cut -d':' -f2)
    local blocks=$(echo "$info" | grep -o '"blocks":[0-9]*' | cut -d':' -f2)

    if [ -z "$progress" ]; then
        log_error "无法获取同步进度"
        exit 1
    fi

    # 输出进度百分比
    percent=$(echo "$progress * 100" | bc -l | xargs printf "%.2f")
    echo -e "${GREEN}同步进度：$percent% （区块高度：$blocks）${NC}"

    # 检查是否已经同步完毕
    if (( $(echo "$progress >= 0.9999" | bc -l) )); then
        echo -e "${GREEN}节点已同步完成。${NC}"
        return 0
    fi

    # 获取上一次记录信息（可选功能：持久化）
    tmp_file="/tmp/.bitcoin_sync_progress"
    now_ts=$(date +%s)

    if [ -f "$tmp_file" ]; then
        last_line=$(tail -n1 "$tmp_file")
        last_ts=$(echo "$last_line" | cut -d',' -f1)
        last_progress=$(echo "$last_line" | cut -d',' -f2)
        last_blocks=$(echo "$last_line" | cut -d',' -f3)

        delta_time=$((now_ts - last_ts))
        delta_progress=$(echo "$progress - $last_progress" | bc -l)
        delta_blocks=$((blocks - last_blocks))

        if (( delta_time > 0 )) && (( $(echo "$delta_progress > 0" | bc -l) )); then
            speed=$(echo "$delta_progress / $delta_time" | bc -l)
            remaining=$(echo "(1 - $progress) / $speed" | bc -l)
            minutes=$(echo "$remaining / 60" | bc -l)
            hours=$(echo "$minutes / 60" | bc -l)

            eta=$(date -d "+$((remaining)) seconds" "+%Y-%m-%d %H:%M:%S")

            echo -e "${YELLOW}预计剩余时间：$(printf "%.1f" $minutes) 分钟（约 $(printf "%.2f" $hours) 小时）"
            echo -e "预计完成时间：$eta${NC}"
        fi
    fi

    # 记录当前进度
    echo "$now_ts,$progress,$blocks" > "$tmp_file"
}
# 显示帮助信息
show_help() {
    echo "Bitcoin节点管理脚本"
    echo ""
    echo "用法: $0 [--force] [命令] [网络类型]"
    echo ""
    echo "选项:"
    echo "  --force   - 强制模式，跳过所有确认提示"
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
    echo ""
    echo "环境变量:"
    echo "  BITCOIN_NETWORK   - 网络类型 (mainnet|testnet, 默认: mainnet)"
    echo "  BITCOIN_DATA_DIR  - 数据目录 (默认: ~/.bitcoin)"
    echo "  BITCOIN_USER      - 运行用户 (默认: 当前用户)"
    echo ""
    echo "示例:"
    echo "  $0 install"
    echo "  $0 --force install"
    echo "  BITCOIN_NETWORK=testnet $0 --force install"
    echo "  $0 status"
    echo "  $0 health"
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
        *)
            log_error "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@"
