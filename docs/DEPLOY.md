# 极核 ZEEHO · 部署教程（NAS / Docker 版）

> 适用脚本：`script/zeeho_box_enhanced.js`（v2.16.45） · 更新 2026-10-29
> 平台：飞牛 fnOS / 群晖 DSM / unRAID / 任意 Docker 主机
> 本教程是上游 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO) 部署教程的 NAS 版改写

---

## 一、两种部署路线

| 路线 | 说明 | 推荐 |
|---|---|---|
| **A. Docker Compose** | 一条命令起容器，签到由容器定时器驱动 | ✅ 首选 |
| **B. 飞牛图形界面** | 文件管理上传 + Docker 项目导入，全程不碰命令行 | 不想用 SSH 时用 |

> 与上游不同，NAS 版**不需要** Loon / Surge / QX / 小火箭，也**不需要** MITM 根证书：
> 面板里的「手机号登录」直接调官方 `loginByPhone` 拿 Token；只有你想用「粘贴 Token」
> 方式时，才需要按上游教程用代理工具抓一次包。

---

## 二、路线 A：Docker Compose

```bash
# 1) 取代码（或直接上传解压，见路线 B）
git clone https://github.com/panghuC8520/zeeho-nas.git
cd zeeho-nas

# 2) 首次建议拉一次上游最新脚本（仓库内已带 v2.16.45）
bash update-script.sh

# 3) 起服务
docker compose up -d --build

# 4) 看日志
docker logs -f zeeho-panel
```

看到 `ZEEHO 面板已启动: http://0.0.0.0:8080/` 即可。

**改端口**：编辑 `docker-compose.yml` 的 `ports:`，例如 `"18080:8080"`，然后
`docker compose up -d`，访问 `http://<IP>:18080/`。

**开密码**：`docker-compose.yml` 里把 `PANEL_AUTH: ""` 改成 `PANEL_AUTH: "admin:你的密码"`，
重启后浏览器会弹 Basic Auth。

**界面开关**（都在 `environment:` 里，`0` 即关闭）：

| 变量 | 作用 |
| :-- | :-- |
| `PC_UI` | 电脑端宽屏适配：≥1024px 时换成左侧导航 + 多列卡片 |
| `PANEL_PATCH` | 设置页开关即时保存，避免被 60 秒自动刷新冲掉 |
| `STRIP_AUTHOR` | 隐藏面板里的作者联系方式 / GitHub / 赞助入口（署名仍在 NOTICE / LICENSE） |

---

## 三、路线 B：飞牛 fnOS 图形界面

1. 应用中心装好「Docker」；
2. 网页 **文件管理** → 存储空间 1 → `docker` 目录（没有就新建）；
3. 上传本仓库 zip 后 **右键 → 解压**，确认结构是
   `/vol1/1000/docker/zeeho-nas/Dockerfile`（**别再套一层同名目录**）；
4. **Docker** 应用 → **项目 / Compose** → 新建项目，名称 `zeeho`，路径选
   `/vol1/1000/docker/zeeho-nas`，能读到 `docker-compose.yml` 就对了；
5. 点 **构建并启动**，等状态变成运行中；
6. 浏览器开 `http://<飞牛IP>:8080/`。

> 也可以走 SMB：地址栏 `\\<飞牛IP>` → 进存储空间 → `docker` 目录 → 把整个
> `zeeho-nas` 文件夹拖进去（**别漏 `script/zeeho_box_enhanced.js`，790KB**）。

---

## 四、通用使用步骤

1. **登录账号**：打开面板 → 右上角设置齿轮 → 账号与导入
   - 手机号登录：填手机号 → 获取验证码 → 填码 → 保存（推荐，免抓包）
   - 粘贴 Token：极核 App 抓包得到的 Token，粘进去会自动去掉 `Bearer `、空格、引号
   - 多账号逐个添加；同 `userId` 会自动合并去重
2. **打卡确认**：签到页点「立即签到」，看日志是否成功；失败会写原因
3. **定时签到**：容器内每天 `CRON_TIME`（默认 07:05）自动跑一轮，无需额外配置；
   想改时间就改环境变量，重启生效
4. **（可选）通知**：设置页填 Bark Key，签到结果 / 充满电 / 车辆离线推手机
5. **（可选）车控密钥**：设置页 → 签名密钥 → 填 32 位 AES 密钥，未填时开/关锁按钮禁用

---

## 五、不用 Docker 直接跑（调试用）

```bash
# 需要 Node >= 18
PORT=8080 CRON_ENABLE=0 DEBUG=1 node server.js
```

面板 `http://127.0.0.1:8080/`，日志直接打屏。适合改 `server.js` 时快速验证。

---

## 六、常见问题

| 问题 | 解决 |
|---|---|
| 面板打不开 | `docker ps` 看容器是否 Up；`docker logs zeeho-panel` 看是否 `EADDRINUSE`（换端口）；确认飞牛防火墙放行 |
| 构建报 `Dockerfile not found` | 解压多套了一层目录，项目路径指到含 `Dockerfile` 的那层 |
| 构建卡在 pull `node:20-alpine` | 配镜像加速，或先 `docker build -t zeeho-panel:local .`，再把 compose 的 `build:` 段换成 `image: zeeho-panel:local` |
| 面板能开但数据全空 | 还没登录账号；`http://<IP>:8080/__diagnostics` 可看 store 里的键名与最近日志 |
| 签到报「操作频繁」 | 多账号限流，脚本内置退避重试；可给不同账号错峰 |
| 接口返回 430 / permit error | 上游密钥或签名变了，`bash update-script.sh && docker compose restart` |
| 车辆数据全为 0 | App 更新后字段变化，等上游适配 |
| 开 / 关锁提示未配置 | 到设置页填 AES 密钥并保存 |
| `update-script.sh` 报 `$'\r': command not found` | 文件被 Windows 改成 CRLF，`sed -i 's/\r$//' update-script.sh` |

---

## 七、文件清单

| 文件 | 说明 |
|---|---|
| `server.js` | 兼容层：宿主对象实现 + HTTP 服务 + 定时签到（本仓库新增） |
| `script/zeeho_box_enhanced.js` | 上游主脚本（面板 + 签到 + 车辆 + 骑行 + 车控），原样分发 |
| `Dockerfile` / `docker-compose.yml` | 容器构建与编排 |
| `update-script.sh` | 从上游拉取最新脚本 |
| `data/store.json` | 运行时生成：账号 Token 与面板配置（**勿提交、勿截图**） |
| `NOTICE.md` / `LICENSE` | 来源与许可声明 |
