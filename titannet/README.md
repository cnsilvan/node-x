
# Titan 边缘节点部署指南 📋

## 安装步骤 🚀

1. **下载并解压 Titan Edge**

   ```bash
   curl -L -o titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz https://github.com/Titannet-dao/titan-node/releases/download/v0.1.19/titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz
   tar -xzvf titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz
   ```

2. **复制可执行文件和库文件**

   进入解压后的目录并复制必要的文件到系统路径：

   ```bash
   cd titan-edge_v0.1.19_89e53b6_linux_amd64
   sudo cp titan-edge /usr/local/bin
   sudo cp libgoworkerd.so /usr/local/lib
   ```

3. **更新共享库缓存**

   确保系统能够找到新安装的库文件：

   ```bash
   sudo ldconfig
   ```

4. **启动 Titan** 🚀

   使用 `screen` 在后台启动 Titan：

   ```bash
   screen -dmS titan-node /usr/local/bin/titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0
   ```

5. **绑定设备** 🔗

   使用你自己的身份码绑定设备：

   ```bash
   /usr/local/bin/titan-edge bind --hash=你的身份码 https://api-test1.container1.titannet.io/api/v2/device/binding
   ```

   请将 `你的身份码` 替换为你的实际身份码。
