#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "===== PORT -> PROCESS ====="
ss -ltnp | awk 'NR==1{next} {print $4"  "$6}' | sed 's/users:((//; s/))//' | sort -u | head -45
echo "===== SERVICES on 21/111/2049 ====="
systemctl list-units --type=service --state=running 2>/dev/null | grep -Ei 'ftp|vsftpd|nfs|rpc|smb|samba|nginx|postgres|rabbit|vault|minio' | head -15
echo "===== SMB.GLOBAL ====="
[ -f /etc/samba/smb.conf ] && grep -Ei 'guest ok|map to guest|security =|server min protocol' /etc/samba/smb.conf | head -10 || echo no-smb.conf
echo "===== SMB SHARES ====="
[ -f /etc/samba/smb.conf ] && grep -E '^\[' /etc/samba/smb.conf | head -12 || true
echo "===== 443 (fnOS https?) ====="
echo | timeout 8 openssl s_client -connect 127.0.0.1:443 -servername localhost 2>/dev/null | grep -E 'subject=|issuer=|Protocol' | head -4
echo "===== 80 / 5666 headers ====="
curl -s -I --max-time 6 http://127.0.0.1:5666/ 2>/dev/null | head -5
echo "===== LISTENING ON ALL IFACES BY IP ====="
ip -o -4 addr show scope global | awk '{print $2, $4}'
