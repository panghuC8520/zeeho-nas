#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PUB=180.108.18.137
echo "===== 打开一条到 公网:445 的连接（保持 8 秒）====="
bash -c "exec 3<>/dev/tcp/$PUB/445; sleep 8" &
BG=$!
sleep 2
echo "----- 本机到 445 的连接 -----"
ss -tn | awk '$4 ~ /:445$/ || $5 ~ /:445$/ {print}' | head -10
echo "----- smbd 的入向连接（若为空，说明 445 不是本机 NAS 应答）-----"
ss -tnp 2>/dev/null | grep smbd | head -10
echo "----- 445 服务端是谁 -----"
ss -ltnp | grep ':445'
wait $BG 2>/dev/null
echo "===== 443/5666 也试一下 ====="
for p in 443 5666 8080; do
  timeout 4 bash -c "echo > /dev/tcp/$PUB/$p" 2>/dev/null && echo "  $p REACHABLE" || echo "  $p blocked"
done
