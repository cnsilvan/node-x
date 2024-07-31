```
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g npm@latest
npm install -g yarn
sudo rm -rf /usr/lib/node_modules/rivalz-node-cli
sudo rm -rf /usr/lib/node_modules/.rivalz-node-cli*
sudo rm ~/.rivalz
npm i -g rivalz-node-cli
rivalz update-version
rivalz run
```
