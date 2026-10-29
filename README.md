<div align="center">

<img src="https://raw.githubusercontent.com/cluck798/ZEEHO/main/ZEEHO.png" width="120" alt="ZEEHO" />

# ZEEHO · NAS
> ⚠️ **非官方部署版**：把上游代理脚本跑成常驻 Web 服务。仅用于个人学习研究，禁止商用。

极核 ZEEHO 签到面板的 **Docker / NAS 包装层**：上游 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO) 的脚本原本依赖 Loon / Surge / Quantumult X / Shadowrocket 运行，本项目用 Node.js 补齐它需要的宿主接口，于是它能直接跑在飞牛 fnOS、群晖、unRAID 或任意装了 Docker 的机器上——**浏览器打开就是面板，签到由容器定时器驱动，手机不用常驻代理**。

> 上游脚本 `script/zeeho_box_enhanced.js` **原样分发（v2.16.45）**，本仓库只新增 `server.js` 这一层兼容层，不改任何业务逻辑与接口签名。

## ✨ 主要特性

### 🖥️ 摆脱代理工具
- 不再需要 Loon / Surge / QX / 小火箭 常驻后台，也不用手机关屏就断签到
- 面板 HTML 由服务端直出，`/api/*` 同源，无跨域、无 MITM 链路
- 手机、平板、电脑浏览器都能开，NAS 内网 IP 直连

### ⏰ 7×24 定时签到
- 容器内定时器每天 `CRON_TIME`（默认 07:05）自动跑一轮全账号签到
- 与面板里的「立即签到」完全等价，结果写日志，可在 `/__diagnostics` 查
- 面板自身的「打开面板补签」逻辑照旧生效，两条路互不冲突

### 🧩 零依赖 · 小体积
- 只用 Node 内置能力（`fetch` / `vm` / `http`），**没有一条 npm 依赖**
- 镜像基于 `node:20-alpine`，构建 1–2 分钟，运行时内存几十 MB

### 🔐 数据自持
- 账号 Token、配置全部落在挂载的 `data/store.json`，不经过任何第三方服务器
- 每次请求独立 `vm` 上下文执行，状态只通过这一个文件共享，互不污染
- 支持 `PANEL_AUTH` 开 HTTP Basic Auth

### 🔄 一键跟上游
- `bash update-script.sh` 从 raw / jsDelivr 双源拉最新脚本并校验体积，重启即生效
- 上游接口变动时，通常更新脚本就能恢复，不必等本仓库发版

### 📱 多端访问
- 响应式面板，桌面/移动浏览器都可用
- 可选反代 + HTTPS 暴露到公网（**务必先开 `PANEL_AUTH`**）

## 🚀 部署

### 方式一：Docker Compose（推荐）

```bash
git clone https://github.com/panghuC8520/zeeho-nas.git
cd zeeho-nas
docker compose up -d --build
```

打开 `http://<主机IP>:8080/` → 设置齿轮 → 账号与导入 → **手机号登录**（发码填码，
面板直接调官方 `loginByPhone`，不需要抓包），或粘贴极核 App 抓到的 Token。

### 方式二：飞牛 fnOS 图形界面

1. 应用中心装好「Docker」；
2. 把仓库放进 `/vol1/1000/docker/zeeho-nas`（文件管理上传 zip 后解压，或 SMB 直接拖）；
3. Docker → **项目 / Compose** → 新建，项目路径选该目录，自动读取 `docker-compose.yml`；
4. 构建并启动，端口映射 `8080`（可改）；
5. 浏览器访问 `http://<飞牛IP>:8080/`。

> 也可直接下载 [zeeho-nas.zip](https://github.com/panghuC8520/zeeho-nas/archive/refs/heads/main.zip) 解压使用。

### 方式三：群晖 / unRAID / 其他

只要支持 Docker Compose 即可，照抄 `docker-compose.yml`：挂一个 `./data` 卷、映射一个端口，
其余全是环境变量。群晖用「项目 → 新增」，unRAID 用 Compose Manager。

## 🖼️ 界面预览

> 界面与上游完全一致（同一份内嵌 HTML），数据来自你自己的账号。

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

上游脚本是代理工具的重写脚本，靠 5 个宿主全局对象工作；本层把它们用 Node 实现：

| 宿主对象 | 本仓库实现 |
| :-- | :-- |
| `$request` | 由收到的 HTTP 请求构造（url / method / headers / body） |
| `$done({response:{status,headers,body}})` | 直接把响应写回浏览器 |
| `$persistentStore.read/write` | `data/store.json` 原子读写 |
| `$httpClient.get/post/put/delete` | Node 内置 `fetch`，回调签名保持 `(err, resp, body)` |
| `$notification.post` | 写入日志（容器内无系统通知） |

另外注入 `$loon = {}`，让脚本自带 `Env` 类判定为 Loon 环境：存储走 `$persistentStore`、
HTTP 走 `$httpClient`，从而绕开脚本里 `got` / `iconv-lite` 的 Node 分支——所以不需要任何 npm 依赖。

## 📦 目录结构

```
zeeho-nas/
├── server.js                    # 兼容层：宿主对象 + HTTP 服务 + 定时签到
├── script/zeeho_box_enhanced.js # 上游脚本 v2.16.45（原样，勿手改）
├── data/store.json              # 运行时生成：账号 Token 与配置（已 gitignore）
├── Dockerfile
├── docker-compose.yml
├── update-script.sh             # 拉取上游最新脚本
├── push-to-github.ps1           # 本机一键把项目推到 GitHub（走 REST API，不需要 git）
└── NOTICE.md                    # 来源与许可声明
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

脚本会从 `raw.githubusercontent.com` 优先、`cdn.jsdelivr.net` 兜底拉取，并校验文件体积。

## ⚠️ 注意事项

- `data/store.json` 里是**真实 Token**：不要提交、不要截图、不要公开部署到公网；外网访问请套反代 + HTTPS + `PANEL_AUTH`。
- 本仓库**不含**任何破解、绕过付费或破解官方 App 的功能，所有接口调用均来自上游脚本。
- 远程控车（开锁 / 坐垫 / 鸣笛 / 充电功率）会真实下发 4G 指令，误触有后果，请按上游说明谨慎使用。
- 官方 App 更新导致接口加密变化时脚本可能失效，等上游适配或自行更新脚本。
- 使用第三方脚本存在账号风控风险，请自行评估。

## 📄 许可协议

- 上游脚本及其业务逻辑遵循上游 [LICENSE](https://github.com/cluck798/ZEEHO/blob/main/LICENSE)：**免费个人使用，禁止售卖、付费分发、付费代安装、捆绑销售及任何商业用途**，转载须保留作者署名与出处。
- 本仓库仅新增部署包装层，同样**仅限个人学习研究**，不提供任何担保；使用产生的一切后果自行承担。
- 详细来源与分工见 [NOTICE.md](NOTICE.md)。

## 🙏 致谢

- 上游项目与全部业务逻辑：[cluck798/ZEEHO](https://github.com/cluck798/ZEEHO)（作者 lucky）——签到、积分、盲盒、车辆状态、骑行数据、车控的协议与实现都来自上游
- 界面由上游脚本内嵌，本仓库未做任何改动
