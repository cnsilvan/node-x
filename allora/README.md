
# Allora 手把手教程 📘

## 安装 Allora 节点 🖥️

> 本文中的指令基于 Ubuntu

### 1. 安装依赖包 📦

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install apt-transport-https ca-certificates curl software-properties-common ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev curl git wget make jq build-essential pkg-config lsb-release libssl-dev libreadline-dev libffi-dev gcc screen unzip lz4 -y
```

### 2. 安装 GoLang (已安装可跳过) 🛠️

```bash
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.22.2.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
source $HOME/.bash_profile
go version
```

### 3. 安装 Docker (已安装可跳过) 🐳

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce
sudo groupadd docker
sudo usermod -aG docker $USER
```

### 4. 安装 Allora 节点 ⚙️

```bash
git clone https://github.com/allora-network/allora-chain.git
cd allora-chain && make install
# 查看版本
allorad version
# 运行节点
sudo docker compose pull
sudo docker compose up -d
```

### 5. 查看节点状态 🔍

```bash
# 查看节点同步状态
allorad status | jq .sync_info
```

### 6. 创建/导入钱包 🔑

```bash
# 创建钱包
allorad keys add nodex
# 导入钱包
allorad keys add nodex --recover
```

### 7. 领取测试币 💧

```bash
# 领取测试币
https://faucet.edgenet.allora.network/
```

### 8. 安装 Worker 🤖

```bash
wallet_seed='填写你的助记词'
cd ~
git clone https://github.com/allora-network/basic-coin-prediction-node.git
cd basic-coin-prediction-node
mkdir worker-data && mkdir worker7-data && mkdir head-data
sudo chmod -R 777 worker-data && sudo chmod -R 777 worker7-data && sudo chmod -R 777 head-data
sudo docker run -it --entrypoint=bash -v ./head-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"
sudo docker run -it --entrypoint=bash -v ./worker-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"
sudo docker run -it --entrypoint=bash -v ./worker7-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"
HEAD_ID=$(cat head-data/keys/identity)
mv docker-compose.yml docker-compose.yml.bak
wget https://raw.githubusercontent.com/cnsilvan/node-x/main/allora/docker-compose.yml
sed -i "s/{HEAD-ID}/$HEAD_ID/g" docker-compose.yml
sed -i "s/WALLET_SEED_PHRASE/$wallet_seed/g" docker-compose.yml
sudo docker compose build
sudo docker compose up -d
```

### 9. 查看 Worker 状态 📈

```bash
curl --location 'http://localhost:6000/api/v1/functions/execute' \
	--header 'Content-Type: application/json' \
	--data '{
	    "function_id": "bafybeigpiwl3o73zvvl6dxdqu7zqcub5mhg65jiky2xqb4rdhfmikswzqm",
	    "method": "allora-inference-function.wasm",
	    "parameters": null,
	    "topic": "1",
	    "config": {
	        "env_vars": [
	            {
	                "name": "BLS_REQUEST_PATH",
	                "value": "/api"
	            },
	            {
	                "name": "ALLORA_ARG_PARAMS",
	                "value": "ETH"
	            }
	        ],
	        "number_of_nodes": -1,
	        "timeout": 2
	    }
	}'
# 正常会返回
{"code":"200","request_id":"e85b975d-98d9-4f79-8b74-x","results":[{"result":{"stdout":"{\"infererValue\": \"2953.110995438121\"}\n\n","stderr":"","exit_code":0},"peers":["xxx"],"frequency":100}],"cluster":{"peers":["xxx"]}}
```

## 10. 问题排查

### 6000端口被占用？🔧

#### 如图所示：
![端口占用问题](https://github.com/user-attachments/assets/b9fa5b6e-33ca-4d92-8189-936491397915)

### 解决方案

#### 方案1：修改占用进程的端口 🚫

1. **查看哪个进程占用了端口**

   ```bash
   lsof -i :6000
   ```

2. **根据查找结果处理相应的进程**

   找到占用该端口的进程后，可以根据实际情况采取适当的措施（如停止或重新配置该进程）。

#### 方案2：修改自己的端口号（从6000改为6001）🔄

1. **修改端口映射**

   ```bash
   sed -i 's/6000:6000/6001:6000/' ~/basic-coin-prediction-node/docker-compose.yml
   ```

2. **重启 Docker 容器**

   ```bash
   cd ~/basic-coin-prediction-node
   sudo docker compose down
   sudo docker compose up -d
   ```

3. **查看 Worker 状态**

   按照步骤9中的方法查看状态时，请记得将指令中的端口号 `:6000` 改为 `:6001`。

