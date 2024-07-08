rm -rf ~/.nubit-light-nubit-alphatestnet-1/keys/
cd nubit-node
~/nubit-node/bin/nubit light init --p2p.network nubit-alphatestnet-1 > output.txt
mnemonic=$(grep -A 1 "MNEMONIC (save this somewhere safe!!!):" output.txt | tail -n 1)
echo $mnemonic > mnemonic.txt
~/nubit-node/bin/nubit light auth admin --node.store ~/.nubit-light-nubit-alphatestnet-1
screen -dmS nubit-node ~/nubit-node/bin/nubit light start  --p2p.network nubit-alphatestnet-1 --core.ip validator.nubit-alphatestnet-1.com --metrics.endpoint otel.nubit-alphatestnet-1.com:4318 --rpc.skip-auth
