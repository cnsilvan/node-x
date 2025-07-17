sed -i 's/http:\/\/mirrors12345.tuna.tsinghua.edu.cn/https:\/\/mirrors.aliyun.com/g' /etc/apt/sources.list
curl -fsSL https://mirrors.ustc.edu.cn/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
ARCH=$(dpkg --print-architecture)
echo -e "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://mirrors.ustc.edu.cn/libnvidia-container/stable/deb/$ARCH /\n#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://mirrors.ustc.edu.cn/libnvidia-container/experimental/deb/$ARCH /" | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu jammy stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
sudo apt update && sudo apt install nvidia-container-toolkit
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker

sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://reg-mirror.qiniu.com",
        "https://docker.1panel.live/"
  ]
}
EOF
nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo apt install nvidia-driver-535 -y
sudo reboot

docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi



#安装rust
# 国外：curl https://sh.rustup.rs -sSf | sh
echo -e '\n# Rust 国内镜像配置\nexport RUSTUP_DIST_SERVER="https://rsproxy.cn"\nexport RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"' >> ~/.bashrc && source ~/.bashrc
source ~/.bashrc
curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh | sh -s -- -y  
mkdir -p ~/.cargo && cat > ~/.cargo/config <<EOF
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true
EOF

#安装golang
wget https://golang.google.cn/dl/go1.24.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tar.gz && echo -e '\n# Go 环境变量\nexport GOROOT=/usr/local/go\nexport GOPATH=$HOME/go\nexport PATH=$PATH:$GOROOT/bin:$GOPATH/bin\nexport GO111MODULE=on\nexport GOPROXY=https://goproxy.cn,direct' >> ~/.bashrc && source ~/.bashrc

curl -L https://risczero.com/install | bash
source ~/.bashrc
cargo install cargo-risczero
rzup install cargo-risczero
rzup install rust
git config --global url."https://gh-proxy.com/github.com/".insteadOf "https://github.com/"
git clone https://github.com/boundless-xyz/boundless.git
cd boundless
git checkout release-0.12
git submodule update --init --recursive
apt install build-essential  pkg-config libssl-dev -y
cargo install --git https://github.com/risc0/risc0 bento-client --branch release-2.1 --bin bento_cli
cargo install --locked boundless-cli
boundless -h
cargo install just
#wsl 权限问题 df -h查找
sudo mount -o remount,exec /run/user/0

cat <<EOL >> .env.base
RUST_LOG=info

REDIS_HOST=redis
REDIS_IMG=redis:7.2.5-alpine3.19

POSTGRES_HOST=postgres
POSTGRES_IMG=postgres:16.3-bullseye
POSTGRES_DB=taskdb
POSTGRES_PORT=5432
POSTGRES_USER=worker
POSTGRES_PASSWORD=password

MINIO_HOST=minio
MINIO_IMG=minio/minio:RELEASE.2024-05-28T17-19-04Z
MINIO_ROOT_USER=admin
MINIO_ROOT_PASS=password
MINIO_BUCKET=workflow

GRAFANA_IMG=grafana/grafana:11.0.0

SEGMENT_SIZE=$SRAM
RISC0_KECCAK_PO2=17

export PRIVATE_KEY=$PRIVATE_KEY
export RPC_URL=$RPC
EOL



