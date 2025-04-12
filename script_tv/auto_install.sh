#!/bin/bash
# File: install_node.sh

LOG_DIR="/var/log/script_tv"
mkdir -p $LOG_DIR
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

main() {
  apt install curl -y
  # 原检测逻辑
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
      ubuntu)
        run_ubuntu_install
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
