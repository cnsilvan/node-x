# Rivalz CLI 安装教程 🚀

### 最低配置要求 🖥️

- **内存**: 4GB
- **CPU**: 4核 (2.2GHz)
- **磁盘**: 50GB SSD
- **网络**: 1Mbps 

### 安装依赖环境 📦
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g npm@latest
npm install -g yarn
```

### 如果之前安装失败或者想重新安装,建议清空之前的数据（第一次运行可跳过） 🔄
```bash
sudo rm -rf /usr/lib/node_modules/rivalz-node-cli
sudo rm -rf /usr/lib/node_modules/.rivalz-node-cli*
sudo rm ~/.rivalz
```

### 安装 Rivalz CLI & screen 📥
```bash
npm i -g rivalz-node-cli
sudo apt install screen -y
```

### 升级 Rivalz CLI ⬆️
```bash
rivalz update-version
```

### 运行 Rivalz CLI ▶️
```bash
rivalz run
```
### 上面输入完配置后，需要后台运行 Rivalz CLI ▶️
```bash
screen -dmS rivalz-node rivalz run
```
### 配置输入 ⚙️
运行后会提示输入配置，按照你的需求逐项输入即可。

![配置输入](https://github.com/user-attachments/assets/c44312e7-9859-4827-b52c-818e70ad46be)

### 运行成功的截图 🎉
![运行成功](https://github.com/user-attachments/assets/e8896d6e-69c1-4c84-9ef2-81479f293210)
