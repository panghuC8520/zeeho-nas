#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
systemctl start nas-firewall.service 2>/dev/null
echo "===== SERVICE ====="
systemctl is-enabled nas-firewall.service; systemctl is-active nas-firewall.service
echo "===== INPUT ====="
iptables -S INPUT
echo "===== NAS_FW_IN (counters) ====="
iptables -L NAS_FW_IN -v -n
echo "===== DOCKER-USER ====="
iptables -S DOCKER-USER
echo "===== DOCKER-USER (counters) ====="
iptables -L DOCKER-USER -v -n | head -12
echo "===== SSHD ====="
sshd -T 2>/dev/null | grep -Ei '^(passwordauthentication|pubkeyauthentication|permitrootlogin)'
echo "===== COMPOSE PANEL ====="
grep -E 'PANEL_AUTH|ports' -A1 /vol1/1000/docker/zeeho-nas/docker-compose.yml | head -8
