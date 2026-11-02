#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "===== WHO IS upnp_service (pid 1920) ====="
cat /proc/1920/cmdline 2>/dev/null | tr '\0' ' '; echo
cat /proc/1920/cgroup 2>/dev/null | head -3
echo "===== upnp / ddns / remote services ====="
systemctl list-units --all 2>/dev/null | grep -Ei 'upnp|ddns|remote|frp|tunnel|ngrok' | head -15
echo "===== fnOS 远程访问相关配置 ====="
grep -Ril 'upnp' /etc/trim /usr/trim/etc 2>/dev/null | head -10
echo "===== 可能的 UPnP 映射记录 ====="
ls -l /var/lib/miniupnpd /run/miniupnpd 2>/dev/null | head
find / -maxdepth 4 -name '*upnp*' -newermt '-30 days' 2>/dev/null | head -10
echo "===== 21 / 2049 服务单元 ====="
systemctl list-units --type=service --state=running 2>/dev/null | grep -Ei 'smbftpd|nfs-server|nfs-mountd|rpcbind' | head
echo "===== SMB 版本策略 ====="
grep -Ei 'min protocol|max protocol|ntlm|signing' /etc/samba/smb.conf 2>/dev/null
echo "===== 面板容器端口绑定 ====="
grep -A2 'ports:' /vol1/1000/docker/zeeho-nas/docker-compose.yml | head -5
echo "===== 近 7 天 SSH 失败来源 TOP ====="
grep -h 'Failed password\|Invalid user' /var/log/auth.log 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -5
echo "===== 登录成功记录 ====="
last -n 5 2>/dev/null | head -6
