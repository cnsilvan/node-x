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
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
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
