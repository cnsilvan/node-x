#!/bin/bash

# 节点部署
function install_node() {
  read -p "请输入节点名称:" node_name
  sudo apt install screen -y
  screen -dmS nubit_$node_name bash -c "curl -sL1 https://nubit.sh | bash"
  echo "部署完成,请等待同步完成"
}
# 查看助记词
function get_mnemonic() {
  echo "助记词:$(cat $HOME/nubit-node/mnemonic.txt)"
}
# 节点状态
function view_status() {
  store=$HOME/.nubit-light-nubit-alphatestnet-1/
  ~/nubit-node/bin/nubit das sampling-stats --node.store $store
}

# 节点日志
function node_log() {
  read -p "请输入节点名称:" node_name
  screen -r nubit_$node_name
}

# 钱包地址
function wallet_addr() {
  store=$HOME/.nubit-light-nubit-alphatestnet-1/
  ~/nubit-node/bin/nubit state account-address --node.store $store
}

# 钱包余额
function check_balance() {
  store=$HOME/.nubit-light-nubit-alphatestnet-1/
  ~/nubit-node/bin/nubit state balance --node.store $store
}

# 钱包列表
function wallet_list() {
  network="nubit-alphatestnet-1"
  node_type="light"
  ~/nubit-node/bin/nkey list --p2p.network $network --node.type $node_type
}

# 钱包秘钥
function wallet_keys() {
  read -p "钱包名称:" wallet_name
  network="nubit-alphatestnet-1"
  node_type="light"
  ~/nubit-node/bin/nkey export $wallet_name --unarmored-hex --unsafe --p2p.network $network --node.type $node_type
}

# 代币转账
function nub_transfer() {
  read -p "收币钱包地址:" address
  read -p "转币数量:" amount
  math=$(echo "$amount * 100000/1" | bc)
  store=$HOME/.nubit-light-nubit-alphatestnet-1/
  ~/nubit-node/bin/nubit state transfer $address $math 400 100000 --node.store $store
}

# 导入钱包
function import_wallet() {
  read -p "设定钱包名称:" wallet_name
  network="nubit-alphatestnet-1"
  node_type="light"
  ~/nubit-node/bin/nkey add $wallet_name --recover --keyring-backend test --p2p.network $network --node.type $node_type
}

# 卸载节点
function uninstall_node() {
  echo "你确定要卸载nubit节点程序吗？这将会删除所有相关的数据。[Y/N]"
  read -r -p "请确认: " response
  case "$response" in
  [yY][eE][sS] | [yY])
    echo "开始卸载节点程序..."
    screen -ls | grep 'nubit_' | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -X -S {} quit
    cd ~
    rm -rf .nubit-light-nubit-alphatestnet-1 .nubit-validator nubit-node
    echo "节点程序卸载完成。"
    ;;
  *)
    echo "取消卸载操作。"
    ;;
  esac
}

# 主菜单
function main_menu() {
  while true; do
    clear
    echo "===================Nubit 一键部署脚本==================="
    echo "轻节点推荐配置：1C1G40G"
    echo "请选择要执行的操作:"
    echo "1. 部署轻节点 install_node"
    echo "2. 查看状态 view_status"
    echo "3. 节点日志 node_log"
    echo "4. 钱包列表 wallet_list"
    echo "5. 钱包地址 wallet_addr"
    echo "6. 查看余额 check_balance"
    echo "7. 获取秘钥 wallet_keys"
    echo "8. 代币转账 nub_transfer"
    echo "9. 导入钱包 import_wallet"
    echo "10. 卸载节点 uninstall_node"
    echo "11. 查看助记词 get_mnemonic"
    echo "0. 退出脚本 exit"
    read -p "请输入选项: " OPTION

    case $OPTION in
    1) install_node ;;
    2) view_status ;;
    3) node_log ;;
    4) wallet_list ;;
    5) wallet_addr ;;
    6) check_balance ;;
    7) wallet_keys ;;
    8) nub_transfer ;;
    9) import_wallet ;;
    10) uninstall_node ;;
    11) get_mnemonic ;;
    0)
      echo "退出脚本。"
      exit 0
      ;;
    *)
      echo "无效选项，请重新输入。"
      sleep 3
      ;;
    esac
    echo "按任意键返回主菜单..."
    read -n 1
  done
}

main_menu
