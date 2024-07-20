#!/bin/bash
cd /root/hub-monorepo

# 获取当前的Git标签
current_tag=$(git describe --tags)

# 获取Docker Hub上的最新镜像标签
docker pull cnsilvan/hubble:latest
docker pull farcaster/hubble:latest

cnsilvan_latest=$(docker inspect --format='{{index .RepoTags 0}}' cnsilvan/hubble:latest | awk -F: '{print $2}')
farcaster_latest=$(docker inspect --format='{{index .RepoTags 0}}' farcaster/hubble:latest | awk -F: '{print $2}')

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
  echo "cnsilvan/hubble:latest is already up-to-date with farcaster/hubble:latest"
fi
