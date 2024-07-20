#!/bin/bash
cd /root/hub-monorepo

# 获取当前的Git标签
current_tag=$(git describe --tags)
docker login

cnsilvan_latest=$(curl -s https://hub.docker.com/v2/repositories/cnsilvan/hubble/tags/?page_size=2 | jq -r '.results[1].name')
farcaster_latest=$(curl -s https://hub.docker.com/v2/repositories/farcasterxyz/hubble/tags/?page_size=2 | jq -r '.results[1].name')

# 比较Docker Hub镜像的最新标签
if [ "$cnsilvan_latest" != "$farcaster_latest" ]; then
  echo "Updating to the latest tag from farcaster: $farcaster_latest"
  # 获取最新的Git标签
  git fetch --tags && git checkout -- apps/hubble/src/cli.ts
  latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1))

  # 更新到最新标签
  git checkout $latest_tag
  sed -i 's/if (totalMemory < 15) {/if (totalMemory < 3) {/' apps/hubble/src/cli.ts
  export PATH="$PATH:$HOME/.local/bin"
  if yarn install && yarn build; then
    echo "Build successful, pushing to Docker..."
    docker buildx build -f Dockerfile.hubble \
      --platform "linux/amd64" \
      --push \
      -t cnsilvan/hubble:${farcaster_latest} \
      -t cnsilvan/hubble:latest .
  else
    echo "Build failed, not pushing to Docker."
  fi
else
  echo "cnsilvan/hubble:latest is already up-to-date with farcasterxyz/hubble:latest"
fi
