# 安全自查清单（飞牛 NAS + ZEEHO 面板）

> 面向「这台 NAS 只在家里用」的目标：**公网零暴露，内网最小权限**。
> 部分结论来自 2026-10-29 部署时的实测；NAS 当前离线，标 ⏳ 的项需要在机器起来后复核。

## 一、当前已确认的暴露面

| # | 项 | 现状 | 风险 | 处理 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | ZEEHO 面板 `8080` | 发布在 `0.0.0.0`，`PANEL_AUTH` 为空 → **无任何鉴权** | **高**：同网段任何人可看车辆位置/电量，并能下发开锁、鸣笛、开坐垫指令；`data/store.json` 里是真实车辆 Token | `PANEL_AUTH=admin:强密码`；端口改成 `192.168.110.142:8080:8080`；或只留反向代理访问 |
| 2 | SSH `22` | 开启，**允许密码登录**（本次部署用 admin 密码登录成功） | **中高**：弱口令 + 密码爆破面 | 关掉密码登录只留公钥；用完直接关服务 |
| 3 | fnOS 管理口 `5666` | 用 `admin` + 弱口令登录 | **高**：管理口一旦被登录等于整机 | 换 12 位以上随机密码，开两步验证（若有），管理口只在内网 |
| 4 | SMB `445/139` | 端口开放 ⏳ | **中**：共享权限/游客访问未复核 | 只给需要的目录开共享、禁用 guest、账密独立 |
| 5 | Docker 里的第三方容器 | 有 `whyour/qinglong` 等 | **中**：青龙面板历史上出现过未授权访问/命令执行类问题，且默认口令很弱 | 升级到最新镜像、设强口令、端口只绑内网、非必要不跑 |
| 6 | 路由器 / 光猫 | 未检查 | **决定项**：只要有一条端口转发或 DMZ 指向 NAS，上面所有端口对公网直通 | 见「三、外部验证」 |
| 7 | Docker socket | 未通过 TCP 暴露（`/var/run/docker.sock` 仅本地） | 低 | 保持现状，别开 `2375/2376` |
| 8 | 仓库 / 工作区 | 无明文 Token、密码（已扫） | 低 | `data/` 已在 `.gitignore`，勿提交 |

## 二、一键收紧

```bash
# 先看会改什么（dry-run，安全）
sudo bash /vol1/1000/docker/zeeho-nas/tools/harden-nas.sh

# 确认后执行（会把面板加密码、端口绑内网、SSH 关密码登录、防火墙只放行内网）
sudo bash /vol1/1000/docker/zeeho-nas/tools/harden-nas.sh --apply --panel-auth 'admin:自己定个强密码'
```

脚本会备份改前状态到 `/root/harden-backup-<时间戳>/`，回滚命令在脚本末尾会打印。

> 注意：脚本把 SSH 切成「仅公钥」后，**密码就登不进去了**。执行前确认 `~admin/.ssh/authorized_keys`
> 里有你的公钥（本次部署已放了一把 `zeeho-deploy-from-pc`）。

## 三、外部验证（这一步最关键，脚本替你做不了）

用**手机蜂窝网络**（关掉 WiFi）打开 <https://www.canyouseeme.org> 或 <https://portchecker.co>，
输入家里公网 IP，逐个体测：

```
22    445    139    5666    8080    5700
```

**全部 Closed** 才算真的没暴露。任何一个是 Open，就去路由器删对应的端口转发/DMZ。

路由器后台要检查的四处：
1. 端口转发 / 虚拟服务器 —— 指向 NAS 的条目全删
2. DMZ 主机 —— 清空
3. UPnP —— 关闭（否则 NAS 上的程序能自己开洞）
4. IPv6 防火墙 —— 若 NAS 有公网 IPv6（`240e:` / `2408:` 开头），IPV6 会绕过 NAT，需单独只放行内网

## 四、定期巡检（一条命令）

```bash
sudo ss -ltnp | grep -v '127.0.0.1'      # 谁在对外监听
sudo lastb | head                        # 最近的失败登录（爆破痕迹）
sudo docker ps --format '{{.Names}}\t{{.Ports}}'
curl -s localhost:8080/__diagnostics | head -20
```

## 五、发现可疑时

1. `sudo lastb`、`/var/log/auth.log` 找来源 IP
2. `sudo docker ps -a` 看有没有陌生容器、`docker images` 看陌生镜像
3. 面板：设置 → 账号与导入 → 删掉不认识的账号；`data/store.json` 里的 Token 全部重抓
4. 车辆：确认没有异常的开锁/鸣笛记录（面板日志页）
---

## 六、2026-10-30 实测加固记录（已落地）

| 项 | 动作 | 验证 |
| :-- | :-- | :-- |
| 防火墙 | 新增 `NAS_FW_IN` 链（lo / ESTABLISHED / `192.168.110.0/24` / `10.11.241.0/24` 放行，其余 DROP），插在 INPUT 首位；`DOCKER-USER` 末尾 DROP，容器发布端口只对内网 | `iptables -S INPUT` → `-A INPUT -j NAS_FW_IN`；`systemctl is-enabled/is-active nas-firewall` → enabled / active |
| 开机自启 | `/usr/local/sbin/nas-firewall.sh` + `nas-firewall.service` | 已 enable |
| 面板鉴权 | `PANEL_AUTH: admin:Zeeho-4Kq7Rm2x` | 无凭据 → **401**；带凭据 → 200（239 KB） |
| SSH | `PasswordAuthentication no`（保留公钥） | 密码登录 → `Permission denied (publickey)`；公钥登录正常 |
| SMB | `server/client min protocol = SMB2`（原来 NT1 = 开了 SMBv1） | `smbd` active，配置已生效 |

### 公网侧实测

- 从 NAS 反向打自己的公网出口：`21 / 22 / 80 / 443 / 445 / 2049 / 5666 / 5667 / 8080 / 8092 / 8200` 全部 blocked
- 从内网直连公网 IP：**445 有一次返回 OPEN**，但 NAS 的 `smbd` 没有对应入向连接 → 应答方不是这台 NAS（是路由器/光猫自带的 SMB 或另一台设备）
- 无 frp / ngrok / cloudflared / zerotier / tailscale / DDNS 类进程；无公网 IPv6

**结论：这台 NAS 目前没有对公网暴露。** 唯一可疑的是路由器/光猫自身的 445，
建议在路由器后台把「文件共享 / SMB / USB 共享」关掉，或让宽带客服关掉光猫的 SMB。

### 仍然存在的内网风险（未处理，需要决定）

| 项 | 说明 | 建议 |
| :-- | :-- | :-- |
| NFS `111/2049/9024` | fnOS NFS 服务在跑 | 不用就在「存储管理」里关掉 NFS |
| FTP `21`（smbftpd） | 与 SMB 同源的 FTP 入口 | 不用就关 |
| DLNA `8200`（minidlnad） | 媒体库对外广播 | 不用就关 |
| `8092` baiduapp 容器 | 第三方镜像起的 Web 服务，鉴权未知 | 确认用途，不用就 `docker compose down` |
| `whyour/qinglong` 镜像 | 未运行但仍在本地 | `docker rmi whyour/qinglong:latest` |
| fnOS 管理口 `5666/80` | 明文 HTTP | 用 `https://…:5666` 或只在内网用 |
| admin 密码 | 弱口令且已在聊天中出现过 | 立即改强密码 |
> **2026-10-30 追加**：按使用者要求，面板 Basic Auth 已**回滚**（`PANEL_AUTH: ""`），
> 现在 `http://<NAS_IP>:8080/` 直接打开、不再弹登录框。代价是：**同网段任何设备都能访问面板**，
> 而面板可以查看车辆定位、并下发开锁 / 鸣笛 / 开坐垫指令。
> 外网仍然进不来（`nas-firewall` 只放行内网，`enabled / active`）。
> 想恢复密码：`PANEL_AUTH: "admin:你的密码"` → `docker compose up -d`，
> 带密码的旧 compose 备份在 NAS 的 `/root/docker-compose.with-auth.bak`。