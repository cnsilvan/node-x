# **Nimble 安装教程（Ubuntu、WSL）** 🚀

### **系统配置要求** 📋

|| **最低配置**          | **推荐**       |
|-------------------|----------------------------------|-----------------------------------|
| **显卡**                          | RTX 2080 or M1/M2/M3 Mac chip sets | RTX 3090+                        |
| **处理器**                    | Core i5 7400                      | Core i7 13700                    |
| **内存**                          | 16GB                              | 16GB                             |
| **磁盘**                   | 40GB                              | 256GB                            |

### **GPU 性能比较（参考）** 🎮

| **系列**    | **设备**  | **速度 (it/s)** | **相对 4090 (%)** |
|---------------|------------|------------------|-------------------|
| **4000 系列** | 4070Ti     | 9 it/s           | 52.9%             |
|               | 4080       | 11 it/s          | 64.7%             |
|               | 4080S      | 12.5 it/s        | 73.5%             |
|               | 4090       | 17 it/s          | 100%              |
| **3000 系列** | 3060Ti     | 5.6 it/s         | 32.9%             |
|               | 3070Ti     | 7.5 it/s         | 44.1%             |
|               | 3080       | 8 it/s           | 47.1%             |
|               | 3080Ti     | 9 it/s           | 52.9%             |
|               | 3090       | 10 it/s          | 58.8%             |
|               | 3090Ti     | 11.8 it/s        | 69.4%             |
| **其他 Nvidia GPU** | 4000 Ada   | 5.9 it/s         | 34.7%             |
|               | 6000 Ada   | 14 it/s          | 82.4%             |
|               | A40        | 8.7 it/s         | 51.2%             |
|               | A100       | 10.2 it/s        | 60.0%             |
|               | A4000      | 5.25 it/s        | 30.9%             |
|               | A4500      | 6.90 it/s        | 40.6%             |
|               | A5000      | 7.92 it/s        | 46.6%             |
|               | A6000      | 9.6 it/s         | 56.5%             |
|               | L40        | 13.6 it/s        | 80.0%             |
|               | L40S       | 13.5 it/s        | 79.4%             |

### **安装依赖环境** 📦

在开始之前，先确保你的系统已经安装了以下必要的依赖包：

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g npm@latest
sudo npm install -g pm2@latest 
sudo apt install make build-essential python3-venv -y
```

### **安装 GoLang (已安装可跳过)** 🛠️

如果你还没有安装 GoLang，请按照以下步骤安装：

```bash
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.22.5.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
source $HOME/.bash_profile
go version
```

### **生成钱包（需要生成两个钱包）** 💰

开始生成钱包，确保你能保存好两个钱包的助记词和地址：

```bash
mkdir ~/nimble && cd ~/nimble
git clone https://github.com/nimble-technology/wallet-public.git
cd wallet-public
make install
~/go/bin/nimble-networkd keys add nodex-master
#输入两次密码
~/go/bin/nimble-networkd keys add nodex-sub
#请保存两个钱包的助记词和钱包地址
```

### **安装挖矿程序** 📥

获取并安装挖矿程序：

```bash
cd ~/nimble
git clone https://github.com/nimble-technology/nimble-miner-public.git
cd nimble-miner-public
make install
```

### **前台运行挖矿程序** ▶️

如果你想在前台运行挖矿程序，可以按照以下步骤操作：

```bash
cd ~/nimble/nimble-miner-public
source ./nimenv_localminers/bin/activate
make run addr=<填写nodex-sub生成的nimble开头的地址> master_wallet=<填写nodex-master生成的nimble开头的地址>
```

### **后台无人值守运行挖矿程序** ▶️

如果你希望在后台无人值守的情况下运行挖矿程序，请使用以下命令：

```bash
pm2 start --name nimble -- bash -c "cd ~/nimble/nimble-miner-public && source ./nimenv_localminers/bin/activate && make run addr=<填写nodex-sub生成的nimble开头的地址> master_wallet=<填写nodex-master生成的nimble开头的地址>" && pm2 save && pm2 startup
# 查看日志
pm2 logs nimble
```
### **余额查询** 💰

- [1.打开网页输入master地址查询](https://www.cryptofiverse.com/nimble-balance)
- 2.本地查询
```bash
cd ~/nimble/nimble-miner-public
make check addr=your_master_wallet
```
### **运行成功的截图** 🎉

成功运行后，可以参考以下截图查看结果：

![运行成功](https://github.com/user-attachments/assets/aafb8c33-34ca-410a-a07d-441722a87295)
