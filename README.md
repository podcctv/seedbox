# MediaHub Seedbox（双节点架构）

该项目采用双机协作模式：

- 下载节点（A）：负责 BT 下载、条目管理、提供 REST API 与管理页面（预览墙）。
- 处理节点（B）：对下载完成的视频进行切片（FFmpeg），生成预览拼图并回传给下载节点。

## 架构概览

下载节点组件：

- Transmission-daemon：BT 下载（Web UI 9091）
- Go (Gin) API：任务队列、条目编辑/删除、预览接收（端口 28000）
- 管理页面：基础配置、搜索与预览墙（挂载到 `/admin`）
- SQLite：存储条目与任务状态（本地 `seedbox.db`）

处理节点组件：

- Python 3 + Requests：轮询 API 获取任务
- FFmpeg：生成预览拼图（默认 `fps=1/10, scale=320:-1, tile=5x5`）
- 回传接口：`POST /jobs/:id/done`（multipart/form-data 上传 `sprite`）

```
[Transmission] --RPC--> [Gin API] --REST--> [管理页面/预览墙]
      |                                ^
      | 轮询任务                        |
      v                                |
[Python+FFmpeg Worker] ---- POST 预览 ----
```

所有 HTTP 请求均需携带 `X-Auth: <token>` 头（详见 SEEDBOX_SPEC.md）。

## 双节点部署

两个节点独立部署，使用 docker compose，且建议共享同一下载与预览存储（NFS/SMB/同机挂载）。

### 下载节点（A）

1) 准备目录并设置环境变量

```bash
cd seedbox
mkdir -p download/downloads download/previews download/watch
export API_TOKEN=CHANGE_ME
# 如需启用 Bitmagnet 搜索，则设置以下变量（可选）
export BITMAGNET_DB_HOST=127.0.0.1
export BITMAGNET_DB_PORT=5432
export BITMAGNET_DB_USER=postgres
export BITMAGNET_DB_PASS=postgres
```

2) 启动 compose

```bash
docker compose -f download/docker-compose.yml up -d
```

3) 访问服务

- Transmission Web UI: `http://localhost:9091`
- 管理页面（含配置/搜索/预览）：`http://localhost:28000/admin/`
- 搜索页直达：`http://localhost:28000/admin/search.html`

默认环境变量（可覆盖）：

- `DOWNLOAD_ROOT=/downloads`
- `PREVIEW_ROOT=/previews`
- `DB_PATH=/app/seedbox.db`
- `ADMIN_DIR=/frontend`

### 处理节点（B）

1) 设置环境变量

```bash
cd seedbox
export API_TOKEN=CHANGE_ME
# 如下载节点非本机或不同网络，请将 API_URL 指向下载节点
# 默认为 http://localhost:28000
```

2) 启动 compose

```bash
docker compose -f worker/docker-compose.yml up -d
```

注意：处理节点需要能访问下载节点返回的视频绝对路径。推荐让两者共享下载目录（例如均挂载同一个 NFS 路径到各自容器的 `/downloads`）。

## 基本操作流程

1. 通过搜索页复制磁力链接至 Transmission（或通过 `POST /tasks/fetch` 注册已下载的本地文件路径）。
2. 下载完成后，下载节点中的条目状态为 `downloaded`。
3. 处理节点轮询 `POST /jobs/next` 获取待处理条目，使用 FFmpeg 生成预览拼图。
4. 处理节点将拼图作为 `sprite` 字段上传至 `POST /jobs/:id/done`，状态变为 `ready`，预览墙可见。

## 开发模式

- Go API（下载节点）：

```bash
cd download
API_TOKEN=dev go run main.go
```

- Python 工人（处理节点）：

```bash
cd worker
pip install -r requirements.txt
API_TOKEN=dev python worker.py
```

## 测试

```bash
pytest
```

## Bitmagnet 数据库

如需磁力数据搜索，请配置环境变量 `BITMAGNET_DB_*` 指向你的 Bitmagnet Postgres 实例。配置后可通过 `/search?q=...` 或管理页面 “Magnet Search” 查询并复制磁力链接。

## 许可说明

仅用于自有或已获授权的媒体内容，勿用于非法传播。
