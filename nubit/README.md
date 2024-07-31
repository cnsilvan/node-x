# Nubit 轻节点部署指南 📋

## 安装步骤 🚀

1. **安装 screen** 🖥️

   ```bash
   sudo apt install screen -y
   ```

2. **部署轻节点** ⛏️

   这一步需要等待一段时间，请耐心等待。

   ```bash
   screen -dmS nubit_test_node bash -c "curl -sL1 https://nubit.sh | bash"
   ```

3. **获取助记词并领取测试币** 💧

   如果获取不到助记词，请等待节点同步完成后再试。
   ```bash
   cat $HOME/nubit-node/mnemonic.txt
   ```

5. **查看部署状态** 🔍

   ```bash
   cd ~/nubit-node/bin
   ./nubit das sampling-stats --node.store $HOME/.nubit-light-nubit-alphatestnet-1/
   ```

   如果显示以下信息：
   
   ```json
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
   ```

   - `is_running` 为 `true` 表示部署成功。
   - `catch_up_done` 为 `true` 表示节点同步完成。

## 使用 Keplr 钱包导入助记词 🔑

1. [下载并安装 Keplr](https://chrome.google.com/webstore/detail/keplr/dmkamcknogkgcdfhhbddcghachkejeap)
2. 打开钱包，选择导入助记词。
3. 粘贴上方获取的助记词，点击“导入”。
4. 等待几秒钟，即可看到你的账户信息。
5. 前往 [Keplr Chains](https://chains.keplr.app) 搜索 “Nubit Alpha Testnet”，点击 “Add”。
6. 在左上角找到“管理链可见性”，选中 “Nubit Alpha Testnet”。
7. 回到 Keplr 查看你的 Nubit 地址，以 "nubit" 开头的即为你的地址。

## 领取测试币 💸

1. 前往 [Nubit Faucet 网站](https://faucet.nubit.org) 每天可领取 0.01 个 NUB。
2. 加入 [Nubit Discord](https://discord.com/invite/nubit)，在 #alpha-testnet-faucet 频道中使用以下命令每天领取 0.03 个 NUB：

   ```bash
   $request 你的nubit地址
   ```

通过以上两种方法，每天最多可以领取 0.04 个 NUB，但总数不能超过 5 个 NUB。
