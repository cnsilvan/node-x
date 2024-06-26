# 导出现有的 crontab 到临时文件
crontab -l > /tmp/current_cron
crontab -l | grep "hubble:latest/cnsilvan"
# 如果 grep 的退出状态码为 1（即没有找到目标条目），则添加新条目
if [ $? -ne 0 ]; then
    echo "*/5 * * * * sed -i 's/farcasterxyz\\/hubble:latest/cnsilvan\\/hubble:latest/g' /root/hubble/docker-compose.yml" >> /tmp/current_cron
    # 将更新后的临时文件重新加载到 crontab
    crontab /tmp/current_cron
fi
rm /tmp/current_cron
