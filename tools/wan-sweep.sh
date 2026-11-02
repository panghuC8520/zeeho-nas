#!/usr/bin/env bash
export LC_ALL=C
PUB=180.108.18.137
echo "===== 从 NAS 打自己公网 IP（判断是否存在端口映射）====="
for p in 21 22 80 443 445 2049 5666 5667 8080 8092 8200; do
  if timeout 4 bash -c "echo > /dev/tcp/$PUB/$p" 2>/dev/null; then echo "  $p  REACHABLE（可能有映射）"; else echo "  $p  blocked"; fi
done
