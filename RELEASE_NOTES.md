## ZEEHO · NAS v1.1.0

部署包更新：新增电脑端宽屏布局、设置页开关即时保存、深链与界面精简开关。

### ✨ 新增

- **电脑端布局（≥1024px）**：左侧竖排导航替代底部 tab 栏，内容区 1240px（≥1600px 为 1460px），首页账号卡片多列网格，设置页 / 车辆页两列，签到日历行高收敛 —— 之前宽屏下是一条 680px 的窄栏
- **设置页开关即时保存**：定时签到 / 车辆状态监控 / 提醒推送 / 签到时间，改动即写入服务端，不再被 60 秒自动刷新重渲染冲掉（原来要手动点页面底部的「保存配置」）
- **深链**：`?zh_tab=cfg|points|vehicle|ride|logs` 直接打开对应页
- **界面精简**：面板内的作者联系方式 / GitHub / 赞助入口默认隐藏，署名与许可保留在 `NOTICE.md`、`LICENSE`
- **调试工具**：`tools/measure.js`、`tools/shot.js` 走 DevTools 协议量布局 / 截图

### 🔧 可配置（docker-compose `environment`）

| 变量 | 默认 | 说明 |
| :-- | :-- | :-- |
| `PC_UI` | `1` | 电脑端宽屏适配，`0` 回到窄栏布局 |
| `PANEL_PATCH` | `1` | 开关即时保存，`0` 回到「点底部保存配置」 |
| `STRIP_AUTHOR` | `1` | 隐藏面板内作者联系方式 / 赞助入口，`0` 恢复 |

### 🚀 用法

```bash
unzip zeeho-nas.zip && cd zeeho-nas
docker compose up -d --build
```

浏览器打开 `http://<主机IP>:8080/` → 设置齿轮 → 账号与导入 → 手机号登录（免抓包）。

### 📄 说明

- 上游脚本 `script/zeeho_box_enhanced.js` 仍为 v2.16.45 原样分发，本仓库只加部署兼容层与上述注入式增强
- 业务逻辑与许可全部来自上游 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO)（非商业许可，禁止售卖 / 付费分发）
