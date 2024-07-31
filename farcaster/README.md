# 没有激励计划
上不上看自己，而且监控软件可能会导致磁盘占满

# Hubble 安装教程 📖🚀

## 配置需求 📋

在开始安装 Hubble 前，请确保您的机器满足以下要求：

- **内存**: 16 GB
- **CPU**: 4 核心
- **存储空间**: 200 GB
- **网络**: 公开 IP 地址，并开放端口 2281 - 2283
- **RPC 端点**: Ethereum 和 Optimism 主网的 RPC URL（可使用 [Alchemy](https://www.alchemy.com/)、[Infura](https://infura.io/) 或 [QuickNode](https://www.quicknode.com/)）

## Docker 安装教程 🐳

### 安装步骤 🔧

1. **克隆仓库**

   首先，克隆 Hubble 仓库到本地：

   ```bash
   git clone https://github.com/farcasterxyz/hub-monorepo.git
   cd hub-monorepo/apps/hubble
   ```
   
2. **安装 Docker (已安装可跳过)** 

   ```bash
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
   sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
   sudo apt-get update
   sudo apt-get install -y docker-ce
   sudo groupadd docker
   sudo usermod -aG docker $USER
   ```
   
3. **生成身份密钥对**

   使用 Docker Compose 创建身份密钥对：

   ```bash
   docker compose run hubble yarn identity create
   ```

4. **配置 `.env` 文件**

   创建 `.env` 文件并设置 Ethereum 和 Optimism 主网的 RPC URL：

   ```bash
   # .env 文件内容
   ETH_MAINNET_RPC_URL=your-ETH-mainnet-RPC-URL
   OPTIMISM_L2_RPC_URL=your-L2-optimism-RPC-URL
   HUB_OPERATOR_FID=your-fid
   ```

5. **启动 Hubble**

   使用 Docker Compose 启动 Hubble：

   ```bash
   docker compose up hubble -d
   ```

   这将启动一个 Hubble 容器，该容器将自动同步网络数据。

6. **查看同步状态**

   通过以下命令查看同步状态：

   ```bash
   docker compose logs -f hubble
   ```

### 升级 Hubble 📈

1. **进入 Hubble 目录**

   ```bash
   cd ~/hubble
   ```

2. **升级 Hubble**

   ```bash
   ./hubble.sh upgrade
   ```

Hubble 的 Docker 安装是简便且快速的方式，可以在不到 30 分钟内完成设置。确保你的配置文件和网络设置正确，以保证节点顺利运行。
