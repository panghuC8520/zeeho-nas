#!/usr/bin/env bash
# ============================================================================
# 飞牛 NAS 一键收紧「公网暴露面」——默认只演练，加 --apply 才真改
#
#   用法：
#     sudo bash tools/harden-nas.sh              # 只看会改什么（dry-run）
#     sudo bash tools/harden-nas.sh --apply      # 真正执行
#     sudo bash tools/harden-nas.sh --apply --panel-auth 'admin:改我'
#
#   做的事：
#     1) 扫一遍对外监听 + 隧道类服务（frp / ngrok / cloudflared / zerotier / tailscale / DDNS / UPnP）
#     2) 防火墙只放行本网段（自动从默认路由推断，如 192.168.110.0/24），其余 INPUT 丢弃
#     3) Docker published 端口在 DOCKER-USER 链里限制为「仅内网」（Docker 会绕过 INPUT，必须单独处理）
#     4) SSH：关掉密码登录，只留公钥
#     5) ZEEHO 面板：加 Basic Auth，并把端口绑定到内网 IP
#     6) 打印一份「还需要你手动确认」的清单（路由器端口映射 / DMZ / UPnP 开关）
#
#   回滚：脚本会把改前的关键状态存到 /root/harden-backup-<时间戳>/
# ============================================================================
set -uo pipefail

APPLY=0
PANEL_AUTH="${PANEL_AUTH:-}"
ZEEHO_DIR="${ZEEHO_DIR:-/vol1/1000/docker/zeeho-nas}"
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --panel-auth) shift; PANEL_AUTH="${1:-}" ;;
    --panel-auth=*) PANEL_AUTH="${arg#*=}" ;;
    --dir=*) ZEEHO_DIR="${arg#*=}" ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  esac
done

TS=$(date +%Y%m%d-%H%M%S)
BK="/root/harden-backup-$TS"
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
run() { if [ "$APPLY" -eq 1 ]; then eval "$@"; else echo "   [dry-run] $*"; fi; }

[ "$(id -u)" -eq 0 ] || { echo "请用 root/sudo 运行"; exit 1; }
mkdir -p "$BK"

# ---------------------------------------------------------------- 1. 现状
say "1. 对外监听（0.0.0.0 / :: 才算对外）"
ss -ltnH 2>/dev/null | awk '{print $4"  "$5}' | sort -u | sed 's/^/   /'

say "1b. 可疑的对外通道（穿透 / 组网 / 动态域名 / UPnP）"
for pat in frpc frps ngrok cloudflared zerotier tailscaled ddns miniupnpd upnp aliddns cloudns; do
  pids=$(pgrep -a "$pat" 2>/dev/null)
  [ -n "$pids" ] && echo "   [$pat] $pids"
done
systemctl list-units --type=service --state=running 2>/dev/null | grep -Ei 'frp|ngrok|cloudflare|zerotier|tailscale|ddns|upnp' | sed 's/^/   /' || true
echo "   （上面为空 = 没发现常见穿透/UPnP 服务；路由器的 UPnP/DMZ 仍需手动确认）"

# ---------------------------------------------------------------- 2. 网段
LAN_CIDR=$(ip -o -4 addr show scope global | awk '{print $4}' | grep -v '^172\.1[7-9]\.' | head -1)
LAN_CIDR=${LAN_CIDR:-192.168.0.0/16}
LAN_NET=$(echo "$LAN_CIDR" | cut -d/ -f1)
say "2. 认定为内网：$LAN_CIDR（如不对，改脚本里的 LAN_CIDR 或用路由器实际网段）"

# ---------------------------------------------------------------- 3. 防火墙
say "3. INPUT 防火墙：仅放行内网 + 已建立连接"
mkdir -p "$BK"
iptables-save > "$BK/iptables.before" 2>/dev/null || true
ip6tables-save > "$BK/ip6tables.before" 2>/dev/null || true

if command -v ufw >/dev/null 2>&1; then
  echo "   检测到 ufw，用它做规则"
  run "ufw --force reset >/dev/null"
  run "ufw default deny incoming"
  run "ufw default allow outgoing"
  run "ufw allow from $LAN_CIDR to any port 22 proto tcp"
  run "ufw allow from $LAN_CIDR to any port 5666 proto tcp"
  run "ufw allow from $LAN_CIDR to any port 8080 proto tcp"
  run "ufw allow from $LAN_CIDR to any port 445 proto tcp"
  run "ufw allow from $LAN_CIDR to any port 139 proto tcp"
  run "ufw --force enable"
else
  echo "   没有 ufw，用 iptables"
  run "iptables -N NAS_LAN_ONLY 2>/dev/null || iptables -F NAS_LAN_ONLY"
  run "iptables -A NAS_LAN_ONLY -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN"
  run "iptables -A NAS_LAN_ONLY -s $LAN_CIDR -j RETURN"
  run "iptables -A NAS_LAN_ONLY -i lo -j RETURN"
  run "iptables -A NAS_LAN_ONLY -j DROP"
  run "iptables -C INPUT -j NAS_LAN_ONLY 2>/dev/null || iptables -I INPUT 1 -j NAS_LAN_ONLY"
fi

say "3b. Docker published 端口：只允许内网访问"
# Docker 的端口发布走 nat/DNAT + DOCKER-USER 链，普通 INPUT 规则管不到
run "iptables -N DOCKER-USER 2>/dev/null || true"
run "iptables -F DOCKER-USER"
run "iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN"
run "iptables -A DOCKER-USER -s $LAN_CIDR -j RETURN"
run "iptables -A DOCKER-USER -i docker0 -j RETURN"
run "iptables -A DOCKER-USER -i br-+ -j RETURN"
run "iptables -A DOCKER-USER -j DROP"

# ---------------------------------------------------------------- 4. SSH
say "4. SSH：关闭密码登录，只留公钥"
cp -a /etc/ssh/sshd_config "$BK/sshd_config.bak" 2>/dev/null || true
if [ "$APPLY" -eq 1 ]; then
  sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
  sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  echo "   已改为仅公钥登录（确认你的公钥在 ~/.ssh/authorized_keys 里再用！）"
else
  echo "   [dry-run] 会把 PasswordAuthentication 改成 no、PermitRootLogin 改成 prohibit-password"
fi

# ---------------------------------------------------------------- 5. 面板
say "5. ZEEHO 面板：加 Basic Auth + 端口只绑内网"
if [ -f "$ZEEHO_DIR/docker-compose.yml" ]; then
  cp -a "$ZEEHO_DIR/docker-compose.yml" "$BK/docker-compose.yml.bak"
  if [ "$APPLY" -eq 1 ]; then
    if [ -z "$PANEL_AUTH" ]; then
      PANEL_AUTH="admin:$(head -c 9 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)"
      echo "   未提供 --panel-auth，已生成随机密码：$PANEL_AUTH"
    fi
    sed -i -E "s|^(\s*)PANEL_AUTH:.*|\1PANEL_AUTH: \"$PANEL_AUTH\"|" "$ZEEHO_DIR/docker-compose.yml"
    sed -i -E "s|^(\s*)- \"?[0-9.]*:?8080:8080\"?|\1- \"$LAN_NET:8080:8080\"|" "$ZEEHO_DIR/docker-compose.yml"
    ( cd "$ZEEHO_DIR" && docker compose up -d >/dev/null 2>&1 ) && echo "   面板已重启（$LAN_NET:8080，Basic Auth 已开）"
    echo "   记下来：$PANEL_AUTH"
  else
    echo "   [dry-run] 会写入 PANEL_AUTH 并把 ports 改成 \"$LAN_NET:8080:8080\""
  fi
else
  echo "   没找到 $ZEEHO_DIR/docker-compose.yml，跳过"
fi

# ---------------------------------------------------------------- 6. 报告
say "6. 还需要你手动确认的（脚本碰不到）"
cat <<'TIP'
   1) 路由器：转发规则 / 虚拟服务器 / DMZ / UPnP —— 只要有一条指向这台 NAS 的 22、445、5666、8080、5700，
      公网就能直连，防火墙拦不住（因为是 WAN→LAN 的 NAT 转发，目标端口照样能进）。
      操作：登录路由器后台，把「虚拟服务器/端口转发」里指向 NAS 的条目全删；
            「DMZ 主机」清空；「UPnP」关掉。
   2) 运营商光猫：很多默认开了 UPnP 或「远程管理」，在光猫后台一并关掉，或让宽带客服关。
   3) 外部验证：用手机蜂窝网络（别连家里 WiFi）打开
        https://www.canyouseeme.org  或  https://portchecker.co
      依次测 22 / 445 / 5666 / 8080 / 5700，全部显示 Closed 才算真的没暴露。
   4) IPv6：如果 NAS 有公网 IPv6（240e:/2408: 开头），它会绕过 NAT 直接可达，
      需要在 NAS 防火墙和路由器 IPv6 防火墙两边都只放行内网。
   5) 弱口令：fnOS 管理口 5666、青龙面板（5700）、SMB 账号，都换成强密码；能开两步验证就开。
TIP

say "备份与回滚"
echo "   改前状态已存：$BK"
echo "   回滚：iptables-restore < $BK/iptables.before ；cp $BK/sshd_config.bak /etc/ssh/sshd_config ；"
echo "         cp $BK/docker-compose.yml.bak $ZEEHO_DIR/docker-compose.yml && docker compose up -d"
echo
[ "$APPLY" -eq 1 ] && echo "✅ 已应用（--apply）" || echo "ℹ️ 只是演练，加 --apply 才会真正修改"
