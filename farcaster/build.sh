curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update
sudo apt install -y yarn cargo cmake htop git libclang-dev g++ autoconf automake libtool curl make unzip
curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v27.2/protoc-27.2-linux-x86_64.zip && unzip protoc-27.2-linux-x86_64.zip -d $HOME/.local
export PATH="$PATH:$HOME/.local/bin"
LIBCLANG_PATH=$(find /usr -name "libclang.so*" -exec dirname {} \; 2>/dev/null | head -n 1)
if [ -z "$LIBCLANG_PATH" ]; then
    echo "libclang not found. Please install libclang and try again."
    exit 1
fi
if [ -n "$BASH_VERSION" ]; then
    PROFILE_FILE="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    echo "Unsupported shell. Please add the environment variable to your shell's profile manually."
    exit 1
fi
if grep -q "export LIBCLANG_PATH=" "$PROFILE_FILE"; then
    echo "LIBCLANG_PATH is already set in $PROFILE_FILE"
else
    # 添加 LIBCLANG_PATH 到配置文件
    echo "export LIBCLANG_PATH=$LIBCLANG_PATH" >> "$PROFILE_FILE"
    echo "LIBCLANG_PATH has been added to $PROFILE_FILE"
    source $PROFILE_FILE
    # 提示用户重新加载配置文件
#    echo "Please run 'source $PROFILE_FILE' to apply the changes."
fi
git clone https://github.com/farcasterxyz/hub-monorepo.git
sed -i 's/if (totalMemory < 15) {/if (totalMemory < 3) {/' hub-monorepo/apps/hubble/src/cli.ts
cd hub-monorepo
DOCKER_COMPOSE_FILE_PATH="apps/hubble/docker-compose.yml"
GRAFANA_DASHBOARD_JSON_PATH="apps/hubble/grafana/grafana-dashboard.json"
GRAFANA_INI_PATH="apps/hubble/grafana/grafana.ini"
mkdir -p grafana
chmod 777 grafana
mkdir -p grafana/data
chmod 777 grafana/data
mkdir -p /var/lib/grafana/plugins
install_docker() {
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        echo "✅ Docker is installed."
        return 0
    fi

    # Install using Docker's convenience script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to install Docker via official script. Falling back to docker-compose."
        curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    rm get-docker.sh

    # Add current user to the docker group
    sudo usermod -aG docker $(whoami)

    echo "✅ Docker is installed"
    return 0
}
install_docker
yarn install
yarn build
