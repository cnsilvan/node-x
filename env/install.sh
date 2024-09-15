function install_docker() {
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
function install_nodejs_and_npm() {
  if command -v node >/dev/null 2>&1; then
    echo "✅ Node is installed.version: $(node -v)"
  else
    echo "Install Nodejs..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  if command -v npm >/dev/null 2>&1; then
    echo "✅ NPM is installed.version: $(npm -v)"
  else
    echo "Install NPM..."
    sudo apt-get install -y npm
  fi
}
function install_pm2() {
  if command -v pm2 >/dev/null 2>&1; then
    echo "✅ PM2 is installed.version: $(pm2 -v)"
  else
    echo "Install PM2..."
    npm install pm2@latest -g
  fi
}
