# 检查空闲磁盘空间，单位为GB
free_space=$(df / | grep / | awk '{print $4}')
free_space_gb=$((free_space / 1024 / 1024))
# 检查空闲空间是否大于100GB
if [ "$free_space_gb" -gt 100 ]; then
  echo "空闲磁盘空间大于100GB，正在执行命令..."
  sudo sed -i 's/^[[:space:]]*#StorageGB = .*/StorageGB = 20/' /root/.titanedge/config.toml
  sudo systemctl restart titan-edge
else
  echo "空闲磁盘空间不足100GB，当前空闲空间为${free_space_gb}GB。"
fi
