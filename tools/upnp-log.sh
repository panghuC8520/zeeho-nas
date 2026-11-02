#!/usr/bin/env bash
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "===== latest upnp log (tail 40) ====="
ls -t /usr/trim/logs/upnp_service_*.log 2>/dev/null | head -1 | xargs -r tail -40
echo "===== grep mapping keywords ====="
grep -hiE 'addportmapping|mapping|external|forward|igd|gateway' $(ls -t /usr/trim/logs/upnp_service_*.log 2>/dev/null | head -3) 2>/dev/null | tail -25
echo "===== trim_machine.conf (upnp/remote flags) ====="
grep -iE 'upnp|remote|ddns|access' /usr/trim/etc/trim_machine.conf 2>/dev/null | head -15
echo "===== upnp.service unit ====="
systemctl cat upnp.service 2>/dev/null | head -25
echo "===== 是否有 fnOS 远程访问(DDNS)配置 ====="
ls -l /usr/trim/etc/ 2>/dev/null | head -20
