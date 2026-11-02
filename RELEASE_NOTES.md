## ZEEHO · NAS v1.2.0

围绕「面板自己就能更新」和「电脑端日历可读性」的一次迭代。

### 🔄 面板内一键更新
- 「设置 → 关于」在检测到新版本时出现「**立即更新服务器脚本**」按钮：raw 优先 / jsDelivr 兜底 → 校验体积（>200KB）与 `#!version` → 原子替换 → **热重载**，不重启容器
- 脚本目录改为挂载 `./script`，更新落到宿主机，`docker compose` 重建也不会回退
- 接口：`POST /api/self-update` → `{ok, from, version, bytes, tookMs}`

### 🖥️ 电脑端签到日历
- **日期与星期上表头对齐**：原来日期格子受 `aspect-ratio:1` 影响变成 56px 方块、贴列左侧，与居中的表头错位；现在格子铺满整列
- **日期数字放大**：11px → 18px 加粗；星期表头 10px → 14px；格子 56 → 66px，圆角 12px
- **补上「下月」按钮**：上游只给了「上月」，`ptMonthShift(1)` 有函数没入口；注入后与「上月」并排，并做全局去重（反复重渲染也不会堆出多个）

### 🧰 运维脚本
- `tools/harden.sh`、`tools/recon.sh`、`tools/verify.sh`、`tools/ports.sh`、`tools/smb-fix.sh`：防火墙/SSH/SMB 收紧与巡检
- `tools/measure.js`、`tools/shot.js`：走 DevTools 协议量布局、截图，排查样式问题用
- `tools/sync-token.ps1`、`tools/push-to-github.ps1`、`tools/make-release.ps1`：不用装 git 也能推送/发版

### 🚀 用法

```bash
unzip zeeho-nas.zip && cd zeeho-nas
docker compose up -d --build
```

浏览器打开 `http://<主机IP>:8080/` → 设置齿轮 → 账号与导入 → 手机号登录（免抓包）。

### 📄 说明

- 上游脚本 `script/zeeho_box_enhanced.js` 原样分发（当前随包为 v2.16.46，面板内可一键跟进后续版本）
- 业务逻辑与许可全部来自上游 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO)（非商业许可，禁止售卖 / 付费分发）