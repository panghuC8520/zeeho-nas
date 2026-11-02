#!/usr/bin/env bash
# 只读巡检：对外监听 / 防火墙 / SSH / 隧道 / 容器 / SMB / 登录失败
export LC_ALL=C
echo "===== LISTEN_TCP ====="
ss -ltn | awk 'NR>1{print $4}' | sort -u
echo "===== LISTEN_UDP ====="
ss -lun | awk 'NR>1{print $4}' | sort -u
echo "===== IP4 ====="
ip -o -4 addr show scope global | awk '{print $2, $4}'
echo "===== IP6_GLOBAL ====="
ip -o -6 addr show scope global 2>/dev/null | awk '{print $2, $4}'
echo "===== NFTABLES(head40) ====="
nft list ruleset 2>/dev/null | head -40
echo "===== IPTABLES_INPUT ====="
iptables -S INPUT 2>/dev/null | head -20
echo "===== IPTABLES_DOCKER_USER ====="
iptables -S DOCKER-USER 2>/dev/null
echo "===== UFW ====="
if command -v ufw >/dev/null 2>&1; then ufw status; else echo no-ufw; fi
echo "===== SSHD_EFFECTIVE ====="
sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords|kbdinteractiveauthentication|x11forwarding)'
echo "===== TUNNELS ====="
pgrep -a -f 'frpc|frps|ngrok|cloudflared|zerotier|tailscaled|ddns|miniupnpd' 2>/dev/null || echo none
echo "===== DOCKER_CONTAINERS ====="
docker ps --format '{{.Names}} | {{.Image}} | {{.Ports}}' 2>&1
echo "===== DOCKER_IMAGES ====="
docker images --format '{{.Repository}}:{{.Tag}}' 2>&1 | head -15
echo "===== SMB_CONF ====="
if command -v testparm >/dev/null 2>&1; then testparm -s 2>/dev/null | grep -Ei 'guest ok|path =|valid users|read only|browseable' | head -25; else echo no-samba; fi
echo "===== FNOS_VERSION ====="
grep -E 'PRETTY_NAME|VERSION_ID' /etc/os-release
uname -a
echo "===== FAILED_LOGIN_COUNT ====="
lastb 2>/dev/null | wc -l
echo "===== SUDOERS_CUSTOM ====="
ls -l /etc/sudoers.d/ 2>/dev/null
echo "===== ZEEHO_PANEL ====="
grep -E 'ports|PANEL_AUTH|PC_UI|STRIP_AUTHOR' /vol1/1000/docker/zeeho-nas/docker-compose.yml 2>/dev/null || echo no-compose
