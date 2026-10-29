# NOTICE · 来源与许可

## 本仓库是什么

`zeeho-nas` 是 [cluck798/ZEEHO](https://github.com/cluck798/ZEEHO) 的**非官方部署包装层**：
把上游的代理脚本（Loon / Surge / Quantumult X / Shadowrocket 用的重写脚本）
包成一个可在 Docker / NAS（飞牛 fnOS、群晖、unRAID 等）上常驻运行的 Web 服务。

- **上游项目**：极核 ZEEHO 多账号签到面板 —— 作者 **cluck798**（署名 lucky）
- **上游仓库**：https://github.com/cluck798/ZEEHO
- **上游脚本版本**：`script/zeeho_box_enhanced.js` v2.16.45（原样分发，未修改）

## 分工

| 文件 | 来源 |
|---|---|
| `script/zeeho_box_enhanced.js` | 上游项目，**原样拷贝**，版权归 cluck798 |
| `server.js`、`Dockerfile`、`docker-compose.yml`、`update-script.sh`、`README.md` | 本包装层，仅为让上游脚本脱离代理工具运行 |
| `data/` | 运行时生成，含账号 Token，**不入库** |

## 许可

1. 上游脚本与其业务逻辑全部遵循上游 LICENSE：**免费个人使用，禁止售卖、付费分发、付费代安装、捆绑销售及任何商业用途**，转载须保留作者署名与出处。
2. 本包装层代码同样**仅限个人学习研究**，不提供任何担保；因使用产生的一切后果由使用者自行承担。
3. 若上游作者认为本仓库不妥，联系后立即删除。

## 免责

- 本项目不含任何破解、绕过付费或破解官方 App 的功能；所有接口调用均来自上游脚本。
- 面板中保存的是你自己的极核账号 Token，请勿公开部署到公网；仓库、截图、Issue 里都不要贴 Token。
