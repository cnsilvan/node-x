```
curl -L -o titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz https://github.com/Titannet-dao/titan-node/releases/download/v0.1.19/titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz

tar -xzvf titan-l2edge_v0.1.19_patch_linux_amd64.tar.gz

cd titan-edge_v0.1.19_89e53b6_linux_amd64

sudo cp titan-edge /usr/local/bin

sudo cp libgoworkerd.so /usr/local/lib

# 更新共享库缓存
sudo ldconfig
sudo apt install screen
#启动titan
screen -dmS titan-node /usr/local/bin/titan-edge daemon start --init --url https://cassini-locator.titannet.io:5000/rpc/v0
# 绑定设备 身份码改成你自己的
/usr/local/bin/titan-edge bind --hash=026C8560-1A11-4949-A084-18BCE49EECA0 https://api-test1.container1.titannet.io/api/v2/device/binding
```
