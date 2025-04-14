#!/bin/bash
# File: install_node.sh

LOG_DIR="/var/log/script_tv"
mkdir -p $LOG_DIR
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

main() {
  apt install curl jq -y
  PID=$(ps -u stv -o pid,cmd | grep -w "script_tv__script4__wallet" | awk '{print $1}')
  Name="Script_TV"

  if [ -n "$PID" ]; then
    echo "$Name is running: $PID"
    exit 1
  else
    echo "$Name is not running"
  fi
  # 原检测逻辑
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
      ubuntu)
        # Extract major version number
        UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
        
        # Check if version is 23 or higher
        if [ "$UBUNTU_VERSION" -ge 23 ]; then
          echo "Ubuntu version $VERSION_ID detected (OK)"
          run_ubuntu_install
        else
          echo "Error: Ubuntu必须大于等于23版本. 当前版本: $VERSION_ID" >&2
          exit 1
        fi
        ;;
      debian)
        run_debian_install
        ;;
      *)
        echo "Unsupported OS" >&2
        exit 1
        ;;
    esac
  else
    echo "OS detection failed" >&2
    exit 1
  fi
}

run_ubuntu_install() {
  echo "Starting Ubuntu installation..."
  apt install curl -y
  curl -sSL https://raw.githubusercontent.com/cnsilvan/node-x/main/script_tv/mainnet_ubuntu_install.sh | bash
}

run_debian_install() {
  echo "Starting Debian installation..."
  apt install curl -y
  curl -sSL https://download.script.tv/files/script_tv-node-mainnet_debian_11_x86_64__install.sh | bash
}

# 执行主函数并记录日志
main 2>&1 | tee "${LOG_DIR}/install_${TIMESTAMP}.log"
