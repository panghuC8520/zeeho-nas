#!/usr/bin/env bash
# ============================================================================
# 收紧这台 NAS 的公网暴露面（真执行版）
#   sudo bash harden.sh --apply [--panel-auth 'admin:密码']
# ----------------------------------------------------------------------------
#   1) 落一套「只放行内网」的防火墙，并做成开机自启（当前 INPUT 策略是 ACCEPT、DOCKER-USER 是空链 = 全裸）
#   2) ZEEHO 面板加 Basic Auth（现在 8080 无鉴权，能看车辆状态并下发开锁指令）
#   3) SSH 关掉密码登录，只留公钥
#   所有改动都会先备份到 /root/harden-backup-<时间戳>/
# ============================================================================
set -uo pipefail

APPLY=0
PANEL_AUTH=""
ZEEHO_DIR=/vol1/1000/docker/zeeho-nas
LAN1=192.168.110.0/24
LAN2=10.11.241.0/24

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --panel-auth) shift; PANEL_AUTH="${1:-}" ;;
    --panel-auth=*) PANEL_AUTH="${1#*=}" ;;
    --lan1=*) LAN1="${1#*=}" ;;
    --lan2=*) LAN2="${1#*=}" ;;
    *) echo "未知参数 $1"; exit 1 ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || { echo "需要 root：sudo bash $0 --apply"; exit 1; }
TS=$(date +%Y%m%d-%H%M%S); BK=/root/harden-backup-$TS; mkdir -p "$BK"
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
step() { echo "   -> $*"; }

say "0. 备份到 $BK"
iptables-save > "$BK/iptables.before" 2>/dev/null || true
cp -a /etc/ssh/sshd_config "$BK/sshd_config.bak" 2>/dev/null || true
[ -f "$ZEEHO_DIR/docker-compose.yml" ] && cp -a "$ZEEHO_DIR/docker-compose.yml" "$BK/docker-compose.yml.bak"
step "ok"

# ----------------------------------------------------------------- 1. 防火墙
say "1. 防火墙：仅内网可访问（LAN1=$LAN1 LAN2=$LAN2）"
FW=/usr/local/sbin/nas-firewall.sh
if [ "$APPLY" -eq 1 ]; then
cat > "$FW" <<EOF
#!/usr/bin/env bash
# 只放行内网，其余丢弃；Docker 发布端口单独在 DOCKER-USER 里限制
set -u
LAN1=$LAN1
LAN2=$LAN2
# --- 主机 INPUT ---
iptables -N NAS_FW_IN 2>/dev/null || true
iptables -F NAS_FW_IN
iptables -A NAS_FW_IN -i lo -j ACCEPT
iptables -A NAS_FW_IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A NAS_FW_IN -s \$LAN1 -j ACCEPT
iptables -A NAS_FW_IN -s \$LAN2 -j ACCEPT
iptables -A NAS_FW_IN -p icmp -j ACCEPT
iptables -A NAS_FW_IN -j DROP
iptables -C INPUT -j NAS_FW_IN 2>/dev/null || iptables -I INPUT 1 -j NAS_FW_IN
# --- Docker 发布端口（DOCKER-USER 是 FORWARD 的第一跳，Docker 会绕过 INPUT）---
iptables -N DOCKER-USER 2>/dev/null || true
iptables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A DOCKER-USER -s \$LAN1 -j RETURN
iptables -A DOCKER-USER -s \$LAN2 -j RETURN
iptables -A DOCKER-USER -i docker0 -j RETURN
iptables -A DOCKER-USER -i br-+ -j RETURN
iptables -A DOCKER-USER -j DROP
exit 0
EOF
chmod +x "$FW"
cat > /etc/systemd/system/nas-firewall.service <<'EOF'
[Unit]
Description=NAS LAN-only firewall (harden)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nas-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable nas-firewall.service >/dev/null 2>&1
"$FW" && step "已应用（INPUT: ESTABLISHED + 内网放行，其余 DROP；DOCKER-USER: 非内网 DROP）"
systemctl is-enabled nas-firewall.service >/dev/null 2>&1 && step "开机自启：已启用"
else
  step "[dry-run] 会写 $FW + systemd 单元并立即生效"
fi

# ----------------------------------------------------------------- 2. 面板鉴权
say "2. ZEEHO 面板：加 Basic Auth"
if [ -f "$ZEEHO_DIR/docker-compose.yml" ]; then
  if [ "$APPLY" -eq 1 ]; then
    if [ -z "$PANEL_AUTH" ]; then
      PANEL_AUTH="admin:$(head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 14)"
      step "未指定密码，已生成：$PANEL_AUTH"
    fi
    sed -i -E "s|^([[:space:]]*)PANEL_AUTH:.*|\1PANEL_AUTH: \"$PANEL_AUTH\"|" "$ZEEHO_DIR/docker-compose.yml"
    ( cd "$ZEEHO_DIR" && docker compose up -d >/dev/null 2>&1 ) && step "面板已重启，Basic Auth = $PANEL_AUTH"
    echo "$PANEL_AUTH" > "$BK/panel-auth.txt"
  else
    step "[dry-run] 会写入 PANEL_AUTH 并 docker compose up -d"
  fi
else
  step "没找到 $ZEEHO_DIR/docker-compose.yml，跳过"
fi

# ----------------------------------------------------------------- 3. SSH
say "3. SSH：关闭密码登录"
AK=/home/admin/.ssh/authorized_keys
if [ -s "$AK" ]; then
  if [ "$APPLY" -eq 1 ]; then
    sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
    if sshd -t; then
      systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
      step "已关闭密码登录（authorized_keys 里有 $(wc -l < "$AK") 把公钥）"
    else
      cp -a "$BK/sshd_config.bak" /etc/ssh/sshd_config
      step "sshd 配置校验失败，已回滚"
    fi
  else
    step "[dry-run] 会设 PasswordAuthentication no"
  fi
else
  step "跳过：$AK 为空，关掉密码登录会把自己锁在外面"
fi

say "完成"
echo "   备份：$BK"
echo "   回滚防火墙：iptables-restore < $BK/iptables.before && systemctl disable --now nas-firewall.service"
echo "   回滚 SSH   ：cp $BK/sshd_config.bak /etc/ssh/sshd_config && systemctl reload ssh"
