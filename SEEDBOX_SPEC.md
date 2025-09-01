# MediaHub（内部代号：seedbox）规格说明

合规声明：系统仅处理自有或已获授权的媒体内容；所有下载与预览均受访问控制。

## 目标

构建双机协作的媒体下载与预览系统：

- 下载节点：BT 下载、预览墙展示及条目编辑/删除，提供 HTTP API。
- 处理节点：对视频进行切片生成预览图，并回传至下载节点。

## 架构总览

```
[Transmission] --RPC--> [Gin API] --REST--> [管理页面/预览墙]
      |                                ^
      | 轮询任务                        |
      v                                |
[Python+FFmpeg Worker] ---- POST 预览 ----
```

下载节点（A）：

- Transmission-daemon：BT 下载（端口 9091）
- Gin API：任务管理、条目 CRUD、预览接收（端口 28000）
- 管理页面：挂载到 `/admin`
- SQLite：存储条目信息及任务状态

处理节点（B）：

- Python 3 脚本：轮询下载节点获取待处理任务
- FFmpeg：生成预览拼图（`fps=1/10, scale=320:-1, tile=5x5`）
- HTTP 客户端：将生成的预览图通过 `POST /jobs/:id/done` 回传

## 技术选型

- 前端：Vue 3 + Vite（管理与预览）
- 后端 API：Go 1.21 + Gin
- BT 客户端：Transmission-daemon
- 数据库：SQLite（应用数据）+ Postgres（Bitmagnet 可选）
- 处理节点脚本：Python 3 + FFmpeg
- 通信方式：HTTP/JSON，简单 Token 鉴权

## 预览墙功能

- 列出所有下载完成的条目及其预览图
- `PATCH /items/:id` 编辑标题、标签等元数据
- `DELETE /items/:id` 删除条目及其文件（实现中仅删除记录）
- 当处理节点上传预览图后，条目状态变为 `ready`

## API 契约（最小集合）

```
GET    /items                          -> 列出条目
POST   /tasks/fetch {path,title?}      -> 注册已下载文件为条目（简化版）
PATCH  /items/:id                      -> 编辑条目
DELETE /items/:id                      -> 删除条目
POST   /jobs/next                      -> 处理节点获取下一个任务
POST   /jobs/:id/done {sprite}         -> 上传预览图（multipart/form-data）
GET    /config                         -> 获取节点配置
POST   /config {downloadDir,port,workerAddr} -> 更新配置
GET    /search?q=keyword               -> 查询 Bitmagnet 并返回磁力链接（可选）
```

鉴权：所有请求需在 Header 中携带 `X-Auth: <token>`。

## 处理节点流程

1. 轮询 `POST /jobs/next` 获取待处理视频的本地路径及任务 ID。
2. 使用 FFmpeg 生成预览拼图：

```bash
ffmpeg -y -i input.mp4 -vf fps=1/10,scale=320:-1,tile=5x5 preview.jpg
```

3. 调用 `POST /jobs/:id/done` 上传 `preview.jpg`。
4. 下载节点保存预览图并更新条目状态为 `ready`。

## 环境变量（下载节点）

- `API_TOKEN`：鉴权 Token（必须）
- `DOWNLOAD_ROOT`：下载目录挂载点（默认 `/downloads`）
- `PREVIEW_ROOT`：预览输出目录挂载点（默认 `/previews`）
- `DB_PATH`：SQLite 文件路径（默认 `./seedbox.db`）
- `ADMIN_DIR`：管理页面静态目录（默认 `../frontend`）
- `BITMAGNET_DB_HOST|PORT|USER|PASS|NAME`：Bitmagnet Postgres（可选，`NAME` 默认 `bitmagnet`）

## 双节点部署说明

- 两个节点各自拥有独立的 `docker compose` 文件（位于 `download/docker-compose.yml` 与 `worker/docker-compose.yml`）。
- 下载与预览目录使用卷挂载以保证持久化并便于共享。
- 处理节点需具备访问下载节点 API 的网络权限，以及访问视频源文件的共享存储权限。

## 测试与恢复

- Python 测试：`pytest`
- 恢复流程：重新启动容器 → 挂载原有数据目录 → 确认 API 与 Transmission 正常工作。
