# **Nimble 安装教程（Ubuntu、WSL）** 🚀

### **最低配置要求** 🖥️

- **显卡**: NVIDIA RTX 2080
- **CPU**: Intel Core i5-7400（4核）
- **磁盘**: 100GB SSD
- **内存**: 16GB

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

### **运行成功的截图** 🎉

成功运行后，可以参考以下截图查看结果：

![运行成功](https://github.com/user-attachments/assets/aafb8c33-34ca-410a-a07d-441722a87295)
