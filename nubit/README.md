# Nubit 轻节点步骤
## 安装步骤
````
# 1.安装screen
sudo apt install screen -y
# 2.部署轻节点 这一步需要等待一段时间，请耐心等待
screen -dmS nubit_test_node bash -c "curl -sL1 https://nubit.sh | bash"
# 3.获取助记词去领水，领完水再继续（如果获取不到，等待节点同步完成再试）
cat $HOME/nubit-node/mnemonic.txt
# 4.查看部署状态
cd ~/nubit-node/bin
./nubit das sampling-stats --node.store $HOME/.nubit-light-nubit-alphatestnet-1/
# 如果显示
{
  "result": {
    "head_of_sampled_chain": 223001,
    "head_of_catchup": 223001,
    "network_head_height": 223001,
    "concurrency": 0,
    "catch_up_done": true,
    "is_running": true
  }
}
is_running为true，则表示部署成功。
catch_up_done为true，则表示节点已经同步完成。
````
## 使用Keplr钱包导入助记词
1. 下载并安装 https://chrome.google.com/webstore/detail/keplr/dmkamcknogkgcdfhhbddcghachkejeap
2. 打开钱包，选择导入助记词
3. 粘贴上方获取的助记词，点击“导入”
4. 等待几秒钟，即可看到你的账户信息
5. 前往 https://chains.keplr.app 搜索“Nubit Alpha Testnet“，点击“Add”
6. 左上角找到管理链可见性-选中” Nubit Alpha Testnet “
6. 回到keplr查看nubit地址,以"nubit"开头的地址即为你的nubit地址。
## 领水
1.前往网站：https://faucet.nubit.org 每天可以领0.01个NUB
2.DC：https://discord.com/invite/nubit 每天可以领0.03个NUB
在#alpha-testnet-faucet上的频道中使用以下命令：
````
$request 你的nubit地址
````
通过上面2个方法，每天可以领到0.04个NUB，但是总数不能超过5个NUB
