# MediaHub（内部代号：seedbox）规格说明（新技术栈）

> **合规声明**：系统仅处理自有或已获授权的媒体内容；所有下载与预览均受访问控制。

## 目标

构建双机协作的媒体下载与预览系统：

- **下载节点**负责 BT 下载、预览墙展示及条目编辑/删除。
- **处理节点**对视频进行切片生成预览图，并回传给下载节点。

## 1. 架构总览

```
[Transmission] --RPC--> [Gin API] --REST--> [Vue 3 Web]
      |                              ^
      | 轮询任务                      |
      v                              |
[Python + FFmpeg Worker] --------POST 预览图-------
```

### 下载节点（A）

- Transmission-daemon：BT 下载，端口 9091
- Gin API：提供任务管理、条目编辑/删除、预览接收等接口，端口 28000
- Vue 3 + Vite 前端：预览墙，端口 3001
- SQLite：存储条目信息及任务状态
- Web 管理页面：配置节点通信参数

### 处理节点（B）

- Python 3 脚本：轮询下载节点获取待处理任务
- FFmpeg：生成预览拼图（如 `fps=1/10, scale=320:-1, tile=5x5`）
- HTTP 客户端：将生成的预览图通过 `POST /api/jobs/:id/done` 回传

## 2. 技术选型

| 模块         | 技术                       |
| ------------ | -------------------------- |
| 前端         | Vue 3 + Vite + Tailwind    |
| 后端 API     | Go 1.21 + Gin              |
| BT 客户端    | Transmission-daemon        |
| 数据库       | SQLite                     |
| 处理节点脚本 | Python 3 + FFmpeg          |
| 通信方式     | HTTP/JSON，简单 Token 鉴权 |

## 3. 预览墙功能

- 列出所有下载完成的条目及其预览图
- `PATCH /items/:id` 编辑标题、标签等元数据
- `DELETE /items/:id` 删除条目及其文件
- 当处理节点上传预览图后，条目状态变为 `ready`

## 4. API 契约（最小集合）

```
GET    /items                          -> 列出条目
POST   /tasks/fetch {uri|infohash}     -> 创建下载任务
PATCH  /items/:id                      -> 编辑条目
DELETE /items/:id                      -> 删除条目与文件
POST   /jobs/next                      -> 处理节点获取下一个任务
POST   /jobs/:id/done {sprite}         -> 上传预览图（multipart/form-data）
GET    /config                         -> 获取节点配置
POST   /config {downloadDir,port,workerAddr} -> 更新配置
```

鉴权：所有请求需在 Header 中携带 `X-Auth: <token>`。

## 5. 处理节点流程

1. 轮询 `POST /jobs/next` 获取待处理视频的本地路径及任务 ID。
2. 使用 FFmpeg 生成预览拼图：
   ```bash
   ffmpeg -i input.mp4 -vf fps=1/10,scale=320:-1,tile=5x5 preview.jpg
   ```
3. 调用 `POST /jobs/:id/done` 上传 `preview.jpg`。
4. 下载节点保存预览图并更新条目状态。

## 6. 环境变量示例（.env）

```
DOWNLOAD_ROOT=/downloads
PREVIEW_ROOT=/previews
TRANS_RPC_URL=http://transmission:9091
API_TOKEN=CHANGE_ME
```

## 7. 部署说明

- 两个节点各自拥有独立的 `docker compose` 文件（位于 `download/docker-compose.yml` 与 `worker/docker-compose.yml`）。
- 下载与预览目录使用卷挂载以保证持久化。
- 处理节点需具备访问下载节点 API 的网络权限。

## 8. 测试与恢复

- 单元测试：`pytest`
- 恢复流程：重新启动容器 → 挂载原有数据目录 → 确认 API 与 Transmission 正常工作。
