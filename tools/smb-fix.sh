#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
TS=$(date +%Y%m%d-%H%M%S)
cp -a /etc/samba/smb.conf "/root/smb.conf.bak.$TS"
sed -i -E 's/^([[:space:]]*)server min protocol = .*/\1server min protocol = SMB2/' /etc/samba/smb.conf
sed -i -E 's/^([[:space:]]*)client min protocol = .*/\1client min protocol = SMB2/' /etc/samba/smb.conf
grep -q '^[[:space:]]*server min protocol' /etc/samba/smb.conf || echo 'server min protocol = SMB2' >> /etc/samba/smb.conf
echo "=== 现在的协议策略 ==="
grep -Ei 'min protocol|max protocol|signing' /etc/samba/smb.conf
smbcontrol smbd reload-config 2>/dev/null || systemctl reload smbd 2>/dev/null || systemctl restart smbd
sleep 1
echo "=== smbd 状态 ==="
systemctl is-active smbd
echo "备份：/root/smb.conf.bak.$TS"
