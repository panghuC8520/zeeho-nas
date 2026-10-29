<div align="center">

<img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/ZEEHO.png" width="120" alt="ZEEHO" />

# ZEEHO · NAS
> ⚠️ 非官方部署版，仅用于学习研究，禁止商用，使用产生一切风险自行承担

极核 ZEEHO 签到面板的 **Docker / NAS 包装层**。上游 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO) 的脚本运行在 Loon / Surge / Quantumult X / Shadowrocket 里，本项目用 Node.js 补齐它依赖的宿主接口（`$request` / `$done` / `$httpClient` / `$persistentStore` / `$notification`），于是它能直接跑在飞牛 fnOS、群晖、unRAID 或任意 Docker 主机上：**浏览器打开就是面板，签到由容器定时器驱动，手机不再需要常驻代理工具。**

上游脚本 `script/zeeho_box_enhanced.js` **原样分发（v2.16.45）**，本仓库只加一层兼容层，不改任何业务逻辑、接口签名与界面。

## ✨ 主要功能

### 🖥️ 免代理工具常驻（本仓库新增）
- 不依赖 Loon / Surge / QX / 小火箭，也不怕手机关屏、清后台、断代理
- 面板 HTML 服务端直出，`/api/*` 同源，无跨域、无 MITM 中转
- NAS 内网 IP 直连，手机 / 平板 / 电脑浏览器都能开，多端同时看
- 零 npm 依赖（只用 Node 内置 `fetch` / `vm` / `http`），镜像 `node:20-alpine`，构建 1–2 分钟
- 账号与配置落在挂载的 `data/store.json`，不出本机；支持 `PANEL_AUTH` 开 Basic Auth
- `bash update-script.sh` 双源（raw + jsDelivr）拉上游最新脚本并校验体积，重启即生效

### 📅 签到 & 积分任务
- 每日自动签到，统计连续签到天数（跨月连签不重置）
- 社区互动任务：发帖、点赞、评论、分享，自动清理临时动态
- 连续签到满 **30 天自动开启盲盒抽奖**
- 积分中心：积分明细、补签卡数量、签到日历、盲盒进度
- 多账号支持，账号异常**隔离运行**；签到限流自动退避重试

### 🚗 车辆状态监控（读取）
- SOC 电量、续航、电压、充电电流、充电状态
- 前后胎压、胎温、今日骑行里程/时长/最高速度
- 坐垫锁 / 整车锁 / 开关机 / 在线状态、GPS 定位 + 地图跳转、服务到期时间
- 充电统计：本月次数、充入电量、电费估算（按设置的电价），充满 / 离线提醒

### 🏍️ 隐藏骑行数据（骑行页）
- 还原官方 App 按车型能力位隐藏的统计：**极速、急加速、急刹、压弯**
- 月度日汇总（`myRideInfo`）+ 轨迹扫描（`ridetrack_v2`）：急刹/压弯按原始轨迹重算
- 点击日期查看每趟行程明细（出发时间 / 里程 / 均速 / 极速 / 急刹 / 压弯），支持轨迹回放与分享海报

### 🎛️ 远程车辆控制（4G 下发指令）
> ⚠️ 会真实操作车辆，请在车辆附近谨慎操作，误触风险自负。首次使用需同意「车控风险确认」。
1. 🔔 寻车（闪灯）
2. 📣 鸣笛寻车
3. 💺 弹开坐垫
4. 🔒 云端开关锁
5. ⚡ 充电功率设置

### 🔔 通知与提醒
- 自定义 Bark Key，签到结果 / 充电充满 / 车辆离线 / 移车提醒推送到手机
- 容器内的 `$notification` 落日志，`/__diagnostics` 可回看

### 🔄 版本自更新
- 面板「设置 → 关于 → 检查更新」双源比对版本号（raw + jsDelivr，避免 CDN 12h 缓存误判）
- 服务器侧同样可以 `bash update-script.sh` 直接把脚本换新

## 🚀 快速部署

```bash
git clone https://github.com/panghuC8520/zeeho-nas.git
cd zeeho-nas
docker compose up -d --build
```

打开 `http://<主机IP>:8080/` → 设置齿轮 → 账号与导入 → **手机号登录**（发码填码，面板直接调官方
`loginByPhone`，不需要抓包），或粘贴极核 App 抓到的 Token。

| 平台 | 做法 |
| :-- | :-- |
| **飞牛 fnOS** | 仓库放进 `/vol1/1000/docker/zeeho-nas`，Docker → 项目/Compose → 新建并选该目录 → 构建启动 |
| **群晖 DSM** | Container Manager → 项目 → 新增 → 选该目录的 `docker-compose.yml` |
| **unRAID** | Compose Manager 新建 stack，粘贴 `docker-compose.yml` |
| **任意 Linux** | 装好 docker + compose 插件，`docker compose up -d --build` |

详细图文步骤见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 🖼️ 在线演示 & 界面预览

> **上游在线演示（免安装、示例数据、不联网）**：https://cluck798.github.io/ZEEHO/
>
> 界面与上游完全一致（同一份内嵌 HTML），本仓库未做任何改动。

| 首页 | 积分 |
| :--: | :--: |
| <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_home.png" width="240" alt="首页" /> | <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_points.png" width="240" alt="积分" /> |

| 车辆 | 设置 |
| :--: | :--: |
| <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_vehicle.png" width="240" alt="车辆" /> | <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_cfg.png" width="240" alt="设置" /> |

| 骑行（隐藏骑行数据） | 骑行明细 |
| :--: | :--: |
| <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_ride.png" width="240" alt="骑行" /> | <img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/screenshots/demo_ride_detail.png" width="240" alt="骑行明细" /> |

## ⚙️ 环境变量

| 变量 | 默认 | 说明 |
| :-- | :-- | :-- |
| `PORT` | `8080` | 面板端口 |
| `TZ` | `Asia/Shanghai` | 时区，决定「每天几点」签到 |
| `CRON_ENABLE` | `1` | `0` 关闭内置定时签到 |
| `CRON_TIME` | `07:05` | 每天签到时刻（24h，容器本地时区） |
| `PANEL_AUTH` | 空 | 形如 `admin:pass`，开启 HTTP Basic Auth |
| `REQ_TIMEOUT_MS` | `180000` | 单次脚本执行上限，多账号别调太小 |
| `DEBUG` | `0` | `1` 把脚本日志打到容器 stdout |
| `ZEEHO_SCRIPT` | `script/zeeho_box_enhanced.js` | 换脚本路径 |

## 🔧 工作原理

上游脚本靠 5 个宿主全局对象工作，本层用 Node 逐个实现：

| 宿主对象 | 本仓库实现 |
| :-- | :-- |
| `$request` | 由收到的 HTTP 请求构造（url / method / headers / body） |
| `$done({response:{status,headers,body}})` | 直接把响应写回浏览器 |
| `$persistentStore.read/write` | `data/store.json` 原子读写 |
| `$httpClient.get/post/put/delete` | Node 内置 `fetch`，回调签名保持 `(err, resp, body)` |
| `$notification.post` | 写入日志（容器内无系统通知） |

另外注入 `$loon = {}`，让脚本自带 `Env` 类判定为 Loon 环境：存储走 `$persistentStore`、HTTP 走
`$httpClient`，从而绕开脚本里 `got` / `iconv-lite` 的 Node 分支——所以不需要任何 npm 依赖。
每个请求在独立 `vm` 上下文执行，状态只通过 `store.json` 共享。

## 📦 目录结构

```
zeeho-nas/
├── server.js                    # 兼容层：宿主对象 + HTTP 服务 + 定时签到
├── script/zeeho_box_enhanced.js # 上游脚本 v2.16.45（原样，勿手改）
├── data/store.json              # 运行时生成：账号 Token 与配置（已 gitignore）
├── docs/DEPLOY.md             # 图文部署说明
├── Dockerfile
├── docker-compose.yml
├── update-script.sh             # 拉取上游最新脚本
├── push-to-github.ps1           # 本机一键推送到 GitHub（REST API，不需要 git）
├── LICENSE                      # 上游非商业许可协议
└── NOTICE.md                    # 来源与分工说明
```

## ❓ 常见问题

| 现象 | 处理 |
| :-- | :-- |
| 构建报 `Dockerfile not found` | 解压多套了一层目录，项目路径要指到真正含 `Dockerfile` 的那层 |
| 构建卡在 pull | 配 Docker 镜像加速，或 `docker build -t zeeho-panel:local .` 后把 compose 的 `build:` 换成 `image:` |
| 8080 打不开 | 端口被占 → 改 `"18080:8080"`；`docker ps` 看容器是否 Up；`docker logs zeeho-panel` 看启动日志 |
| `update-script.sh` 报 `$'\r'` | 文件被 Windows 改成 CRLF，`sed -i 's/\r$//' update-script.sh` |
| 面板能开但没数据 | 还没登录账号；`/__diagnostics` 可看版本、store 键名、最近日志 |
| 签到报「操作频繁」 | 多账号限流，脚本已内置退避重试；可错峰或用不同 `CRON_TIME` 的多个实例 |
| 接口全 430 / permit error | 上游密钥或签名规则变了，`bash update-script.sh` 后重启 |

## 🔄 更新上游脚本

```bash
bash update-script.sh && docker compose restart
```

脚本优先 `raw.githubusercontent.com`、兜底 `cdn.jsdelivr.net`，并校验文件体积（小于 200KB 视为失败）。

## ⚠️ 注意事项

- `data/store.json` 里是**真实 Token**：不要提交、不要截图、不要公开部署到公网；外网访问请套反代 + HTTPS + `PANEL_AUTH`。
- 本仓库**不含**任何破解、绕过付费或破解官方 App 的功能，所有接口调用均来自上游脚本。
- 远程控车会真实下发 4G 指令，误触有后果，请按上游说明谨慎使用。
- 官方 App 更新导致接口加密变化时脚本可能失效，等上游适配或自行更新脚本。
- 使用第三方脚本存在账号风控风险，请自行评估。

## 📄 许可协议

- 上游脚本及其业务逻辑遵循上游 [LICENSE](LICENSE)：**免费个人使用，禁止售卖、付费分发、付费代安装、捆绑销售及任何商业用途**，转载须保留作者署名与出处。
- 本仓库仅新增部署包装层，同样**仅限个人学习研究**，不提供任何担保；使用产生的一切后果自行承担。
- 来源与分工见 [NOTICE.md](NOTICE.md)。若上游作者认为本仓库不妥，联系后立即删除。

## 🙏 致谢

- 上游项目与全部业务逻辑：[cluck798/ZEEHO](https://github.com/cluck798/ZEEHO)（作者 lucky）——签到、积分、盲盒、车辆状态、骑行数据、车控的协议与实现全部来自上游
- 界面由上游脚本内嵌，本仓库未做任何改动
