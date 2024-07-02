#!/bin/bash
cd /root/hub-monorepo
# 获取当前的Git标签
current_tag=$(git describe --tags)
# 获取最新的Git标签
git fetch --tags && git checkout -- apps/hubble/src/cli.ts
latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1))
# 比较最新标签和当前标签
if [ "$latest_tag" != "$current_tag" ]; then
  echo "Updating to the latest tag: $latest_tag"
  # 更新到最新标签
  git checkout $latest_tag
  sed -i 's/if (totalMemory < 15) {/if (totalMemory < 3) {/' apps/hubble/src/cli.ts
  export PATH="$PATH:$HOME/.local/bin"
  if yarn install && yarn build; then
    echo "Build successful, pushing to Docker..."
    docker buildx build -f Dockerfile.hubble \
    --platform "linux/amd64" \
    --push \
    -t cnsilvan/hubble:${HUBBLE_VERSION} \
    -t cnsilvan/hubble:latest .
  else
    echo "Build failed, not pushing to Docker."
  fi
  
else
  echo "Already at the latest tag: $current_tag"
fi

