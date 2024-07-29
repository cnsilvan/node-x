# Allora 手把手教程

## 安装 Allora 节点

> 文中指令基于ubuntu

1. 安装依赖包

``` bash
sudo apt update & sudo apt upgrade -y
sudo apt install apt-transport-https ca-certificates curl software-properties-common ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev curl git wget make jq build-essential pkg-config lsb-release libssl-dev libreadline-dev libffi-dev gcc screen unzip lz4 -y
```

2.安装golang(已安装则跳过)

``` bash
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.22.2.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
source $HOME/.bash_profile
go version
```

3.安装docker(已安装则跳过)

``` bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
sudo echo | add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce
sudo groupadd docker
sudo usermod -aG docker $USER
```

4.安装Allora节点

``` bash
git clone https://github.com/allora-network/allora-chain.git
cd allora-chain && make install
# 查看版本
allorad version
# 运行节点
sudo docker compose pull
sudo docker compose up -d
```
5.查看节点状态

``` bash
# 查看节点同步状态
allorad status | jq .sync_info
```
6.创建/导入钱包

``` bash
# 创建钱包
allorad keys add nodex
# 导入钱包
allorad keys add nodex --recover
```
7.领水

``` bash
# 领取测试币
https://faucet.edgenet.allora.network/
```
8.安装worker

``` bash
wallet_seed='填写你的助记词'
cd ~
git clone https://github.com/allora-network/basic-coin-prediction-node.git
cd basic-coin-prediction-node
mkdir worker-data && mkdir worker7-data && mkdir head-data
sudo chmod -R 777 worker-data &&sudo chmod -R 777 worker7-data && sudo chmod -R 777 head-data
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
9.查看worker状态

``` bash
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
```
