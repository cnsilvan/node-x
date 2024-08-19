# **NetWork3.AI 安装教程（Ubuntu）** 🚀

### **安装依赖环境** 📦

在开始之前，先确保你的系统已经安装了以下必要的依赖包：

```bash
sudo apt-get install -y net-tools curl make clang pkg-config libssl-dev build-essential jq lz4 gcc unzip
```

### **下载并安装程序** 📥

```bash
curl -L https://network3.io/ubuntu-node-v2.1.0.tar | tar -xf -
cd ubuntu-node
bash manager.sh up
```
运行完毕后 按照提示打开

http://account.network3.ai:8080/main?o=x.x.x.x%3A8080

x.x.x.x填写服务器ip

![image](https://github.com/user-attachments/assets/0ea7384d-9847-4a7c-afda-9fa29bf0c7ec)
点击页面中的加号，需要填写key
### **Key查询** 💰
```bash
bash manager.sh key
```
填写key，即完成安装

