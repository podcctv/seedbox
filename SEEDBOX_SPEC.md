# MediaHub（内部代号：seedbox）

> **合规声明**：本系统仅处理**自有或已获授权**的媒体内容；提供访问控制、审计与下架机制；仅**只读**连接 Bitmagnet Next Web 的数据库用于**元数据检索**，不对外提供公共索引或未授权分发。

**目标**：双机协同的媒体检索 → 受控获取 → 转码/预览 → 受限展示系统。要求：

* **全 Docker 部署**；**数据持久化**；**快速恢复**；**界面简洁美观**
* 未登录仅可看**预览切片**；登录后可**播放(HLS)/收藏**；管理员可**创建任务/删除/配置**
* 所有连接参数与服务地址可在**后台**配置

---

## 1. 架构总览

```
[Bitmagnet Postgres (RO)]  -->  API(search)  --> Web 前端(Next.js)
                                   |                 |
                                   |                 v
                             下载引擎(qB) <---- 管理员创建任务
                                   |
                          (完成回调 webhook)
                                   v
[展示节点 A]  <--- rclone/rsync --->  [处理节点 B]
 MinIO(S3) <--- 回传预览/HLS ---  FFmpeg Worker
   |  ^
   |  └-- Web/HLS 播放(鉴权)
   └-- 预览图匿名访问(可选)
```

**节点与服务**

* **展示节点（A）**：`gateway(Nginx|Traefik)`、`web(Next.js)`、`api(FastAPI|Node)`、`app-postgres`、`redis`、`minio`、`fetcher(qBittorrent-nox)`
* **处理节点（B）**：`worker-ffmpeg`、`rclone-agent`（与 MinIO 交互）
* **外部只读依赖**：`bitmagnet_pg_ro`（Bitmagnet Next Web 的 Postgres 只读连接）

---

## 2. 技术选型

* **Web**：Next.js 14 + Tailwind（深色简洁 UI，SSR/CSR 皆可）
* **API**：FastAPI（Python 3.11+，pydantic，Uvicorn），或 Node.js（NestJS）二选一
* **下载引擎**：qBittorrent-nox（Web API 受内网限制）；完成回调触发 API
* **对象存储**：MinIO（S3 兼容），存放预览图（sprites）与 HLS 切片
* **转码**：FFmpeg（HLS + 预览拼图/场景抽帧）
* **数据库**：Postgres（App DB）；**另有** Bitmagnet Postgres（只读）
* **队列/缓存**：Redis（RQ/BullMQ）
* **反代/鉴权**：Nginx（`auth_request` → API 校验 JWT）

---

## 3. 权限模型

* **guest**：浏览目录、查看预览图；**禁止**播放/编辑/删除
* **user**：在 guest 基础上**可播放(HLS)/收藏**
* **admin**：在 user 基础上**可创建任务/编辑标签/删除/修改配置**
* **认证**：JWT；`/hls/*` 与下载端点由网关 `auth_request` 保护

---

## 4. 前端页面

* `/login`：登录
* `/`：搜索框 + 热门演职员/标签入口
* `/actors`、`/actors/:id`：按演职员聚合
* `/tags`、`/tags/:id`：按标签/类型聚合
* `/items/:id`：详情页（预览拼图、**登录后**HLS 播放、授权下载、收藏/删除）
* `/admin/config`：后台配置（服务器 IP、端口、只读 DSN、S3、下载引擎、FFmpeg 预设等）

---

## 5. API 契约（Minimal）

> 语言无关；如用 FastAPI 请生成 OpenAPI 并导出 `openapi.yaml`。

```
POST /auth/login               -> { token, role, exp }
GET  /auth/verify              -> 2xx/401 (给网关 auth_request 使用)

GET  /search                   -> 来自 bitmagnet_pg_ro 的只读搜索（q、actor、tag、res...）
POST /tasks/fetch {infohash|uri}    [admin]  # 创建受控下载任务

POST /webhooks/fetcher_done {hash,name,root} # 下载完成回调
POST /jobs/done {item_id, preview_key, hls_key, meta} # B 节点处理完成回调

GET  /items/:id
POST /items/:id/favorite       [user+]
DELETE /items/:id              [admin]

GET  /catalog/actors|/catalog/tags
GET  /catalog/actors/:id | /catalog/tags/:id
```

---

## 6. 数据模型（App DB）

```sql
-- users
id UUID PK, username TEXT UNIQUE, password_hash TEXT, role TEXT CHECK IN ('guest','user','admin'),
created_at TIMESTAMPTZ DEFAULT now()

-- items
id UUID PK, infohash TEXT, title TEXT, size_bytes BIGINT, duration_sec INT NULL,
source TEXT CHECK IN ('bitmagnet','manual'), status TEXT CHECK IN ('indexed','downloading','staging','processing','ready','failed'),
preview_key TEXT, hls_key TEXT, download_path TEXT NULL,
created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now()

-- actors/tags (与多对多表)
actors(id UUID PK, name TEXT UNIQUE)
item_actors(item_id UUID FK, actor_id UUID FK)

tags(id UUID PK, name TEXT, type TEXT CHECK IN ('genre','quality','language','other'))
item_tags(item_id UUID FK, tag_id UUID FK)

-- jobs（任务流水）
jobs(id UUID PK, item_id UUID FK, stage TEXT, status TEXT, payload JSONB, log TEXT,
     created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now())
```

---

## 7. 转码与预览（FFmpeg）

* **预览拼图（每 10s 1 帧，5×8）**
  `ffmpeg -i INPUT -vf "fps=1/10,scale=480:-1,tile=5x8" -frames:v 40 OUT/sprite.jpg`
* **场景抽帧（代表性更好，可选）**
  `ffmpeg -i INPUT -vf "select='gt(scene,0.35)',scale=480:-1,tile=6x5" -vsync vfr OUT/scene.jpg`
* **HLS（4s 分片，主档）**

  ```
  ffmpeg -i INPUT -c:v libx264 -preset veryfast -crf 22 -profile:v main \
         -g 48 -keyint_min 48 -sc_threshold 0 -c:a aac -b:a 128k \
         -hls_time 4 -hls_playlist_type vod \
         -hls_segment_filename OUT/hls/seg_%05d.ts OUT/hls/index.m3u8
  ```

---

## 8. Docker 与持久化（骨架）

> 实际仓库请拆分为 `compose.serve.yml`（节点 A）与 `compose.transcode.yml`（节点 B）

```yaml
# 仅示例，生成器需产出真实 compose 文件
volumes:
  pgdata: {}
  redisdata: {}
  miniodata: {}
  qb_conf: {}
  qb_downloads: {}
  api_storage: {}

services:
  gateway: { image: nginx:alpine, volumes: [...], depends_on: [api, web], restart: always }
  web:     { image: ghcr.io/org/seedbox-web:latest, env_file: [.env], restart: always }
  api:     { image: ghcr.io/org/seedbox-api:latest, env_file: [.env], volumes: ["api_storage:/app/storage"], restart: always }
  app-postgres: { image: postgres:16, environment: {...}, volumes: ["pgdata:/var/lib/postgresql/data"], restart: always }
  redis:   { image: redis:7, command: ["redis-server","--appendonly","yes"], volumes: ["redisdata:/data"], restart: always }
  minio:   { image: minio/minio, command: server /data --console-address ":9001", volumes: ["miniodata:/data"], restart: always }
  fetcher: { image: lscr.io/linuxserver/qbittorrent:latest, volumes: ["qb_conf:/config","qb_downloads:/downloads","./scripts:/scripts:ro"], restart: always }
```

**持久化**：Postgres/Redis/MinIO/qB 配置与下载目录均为卷或绑定目录。
**备份**：

* `pg_dump` 每日 → `s3://backup/db/{date}.sql.gz`（保留 14 天）
* `minio` buckets（`previews/`, `hls/`）用 `rclone sync` 定期镜像

---

## 9. 网关鉴权（Nginx 片段）

```nginx
# /hls/ 与 /downloads/ 受保护
location /hls/ {
  auth_request /auth;
  proxy_pass http://minio:9000/hls/;
}
location = /auth {
  internal;
  proxy_pass http://api:8000/auth/verify; # 2xx 放行；401/403 拦截
}
```

---

## 10. 后台配置项（示例）

```yaml
bitmagnet:
  pg_dsn_ro: "postgresql://ro_user:***@host:5432/bitmagnet"

fetcher:
  baseurl: "http://qbittorrent:8080"
  auth: { user: "admin", pass: "***" }
  download_root: "/downloads"
  on_complete_webhook: "https://api.example.com/webhooks/fetcher_done"

transfer:
  to_cpu:  "sftp://10.8.0.2/inbox"
  back_s3: "s3://minio"

cpu_worker:
  inbox: "/inbox"
  outbox: "/outbox"
  ffmpeg:
    preview: { mode: tile, fps: "1/10", scale: "480:-1", tile: "5x8" }
    hls: { preset: veryfast, crf: 22, segment: 4, audio_bitrate: "128k" }

s3:
  endpoint: "http://minio:9000"
  access_key: "***"
  secret_key: "***"
  buckets: { previews: "previews", hls: "hls" }
  public_previews_base: "https://cdn.example.com/previews/"
  protected_hls_base:  "https://media.example.com/hls/"

auth:
  jwt_secret: "***"
  jwt_exp_hours: 72

ui:
  theme: "dark"
  brand: "seedbox"

network:
  serve_node_ip: "10.8.0.1"
  transcode_node_ip: "10.8.0.2"
```

---

## 11. `.env.example`（生成器需据此创建 .env）

```
APP_DB_NAME=mediahub
APP_DB_USER=mediahub
APP_DB_PASS=CHANGE_ME
APP_DB_HOST=app-postgres
APP_DB_PORT=5432

BITMAGNET_RO_DSN=postgresql://ro_user:CHANGE@bitmagnet-db:5432/bitmagnet

REDIS_URL=redis://redis:6379/0

MINIO_ENDPOINT=http://minio:9000
MINIO_ACCESS_KEY=CHANGE_ME
MINIO_SECRET_KEY=CHANGE_ME
MINIO_BUCKET_PREVIEWS=previews
MINIO_BUCKET_HLS=hls

JWT_SECRET=CHANGE_ME
JWT_EXP_HOURS=72

QBT_BASEURL=http://qbittorrent:8080
QBT_USER=admin
QBT_PASS=CHANGE_ME

API_PUBLIC_BASE=https://api.example.com
WEB_PUBLIC_BASE=https://seedbox.example.com
```

---

## 12. 开发与恢复

* 本地开发：`docker compose up -d`
* 健康检查：`GET /healthz`（web/api/worker）
* 备份恢复：拉起 compose → 恢复数据库 dump → 确认 S3 buckets → 校验 `/auth/verify` 与 `/hls/*`

---

## 13. 任务清单（Codex TODO）

* [x] 生成 `compose.serve.yml` 与 `compose.transcode.yml`（含卷/网络/依赖）
* [x] API 项目脚手架（FastAPI / NestJS 二选一），实现本规范最小接口集
* [x] OpenAPI 文档 `openapi.yaml` 自动导出
* [ ] Web 前端（Next.js）页面与路由；主题暗色；HLS 播放用 `hls.js`
* [x] Nginx 网关与 `auth_request` 配置；仅 `/previews/*` 允许匿名
* [x] qB 完成回调脚本 `/scripts/on-complete.sh "%I" "%N" "%R"`，指向 `/webhooks/fetcher_done`
* [x] Worker 容器：FFmpeg 命令封装；读 inbox，出 outbox，rclone 回传 MinIO
* [x] App DB 初始化迁移（users/items/actors/tags/jobs）
* [ ] 后台配置 UI：保存到 App DB，并支持热更新/重载
* [x] 备份脚本：`pg_dump` → MinIO；`rclone sync` → 备份 bucket
* [x] 基本审计日志（登录、创建任务、播放、删除）

---

## 14. 验收标准

* [ ] 未登录访问 `/hls/…` → 401；访问 `/previews/…` → 200
* [ ] 一条端到端流程可跑通：检索 → 受控下载 → 回调 → 传 CPU → 生成预览 & HLS → 回传 MinIO → 展示
* [ ] 管理页可修改连接信息（只读 DSN/S3/下载引擎/FFmpeg 预设等）并生效
* [ ] 重建容器后数据保持（DB/S3/配置/qB 下载目录）
* [ ] OpenAPI 文档与 README 指令完整，CI 构建通过

---

**备注**

* 任何“获取/分发”动作仅用于**授权内容**；下载引擎 Web UI 与 API 均不暴露公网。
* 如需多清晰度自适应，后续在 Worker 增加 ABR 多码率 HLS（`-var_stream_map`）。

---

> 将本文件保存为项目根目录的 `README.md` 或 `SEEDBOX_SPEC.md`，然后让 Codex 按“任务清单（Codex TODO）”生成与完善代码即可。
