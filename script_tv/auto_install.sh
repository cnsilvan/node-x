#!/bin/bash

# 检测系统类型
if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
        ubuntu)
            echo "检测到Ubuntu系统，开始执行安装..."
            curl -sSL https://raw.githubusercontent.com/cnsilvan/node-x/main/script_tv/mainnet_ubuntu_install.sh | bash -s --
            ;;
        debian)
            echo "检测到Debian系统，开始执行安装..."
            curl -sSL https://download.script.tv/files/script_tv-node-mainnet_debian_11_x86_64__install.sh | bash -s --
            ;;
        *)
            echo "错误：不支持的操作系统 $ID"
            exit 1
            ;;
    esac
else
    echo "错误：无法检测操作系统"
    exit 1
fi
