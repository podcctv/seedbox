# MediaHub Seedbox（双节点部署指南）

MediaHub Seedbox 是一个双机协作的媒体下载与预览系统。

- 下载节点（A）：运行 Transmission（BT 下载）、Go(Gin) API、管理页（预览墙），使用 SQLite 存储。
- 处理节点（B）：运行 Python 3 Worker，调用 FFmpeg 生成预览拼图，并将结果回传至下载节点。

所有 HTTP 请求必须携带 `X-Auth: <token>`（详见 `SEEDBOX_SPEC.md`）。

## 架构概览

下载节点（A）：
- Transmission：Web UI 端口 `9091`，BT 端口 `51413/tcp, 51413/udp`
- Gin API：端口 `28000`
- 管理与预览墙：挂载在 `GET /admin`
- SQLite：应用数据存储（默认 `seedbox.db`）

处理节点（B）：
- Python 3 Worker：轮询 `POST /jobs/next`
- FFmpeg：生成预览拼图（默认滤镜：`fps=1/10,scale=320:-1,tile=5x5`）
- 回传接口：`POST /jobs/:id/done`（`multipart/form-data` 字段名 `sprite`）

```
[Transmission] --RPC--> [Gin API] --REST--> [管理/预览墙]
      |                                ^
      | 轮询任务                        |
      v                                |
[Python+FFmpeg Worker] ---- POST 预览 ----
```

## 部署前准备

- Docker 与 Docker Compose（建议 v2）
- 两台主机网络互通（开放端口：下载节点 `28000, 9091, 51413/tcp, 51413/udp`）
- 共享存储：下载节点与处理节点应“在宿主机层面”共享同一下载目录，并尽量保持相同的挂载路径（NFS/SMB/同一台主机挂载）。
- 鉴权令牌：为两个节点设置相同的 `API_TOKEN`。
- 可选：Bitmagnet Postgres 数据库（用于磁力搜索）。

目录约定（仓库根目录执行）：
```bash
mkdir -p download/downloads download/previews download/watch
```

> Windows PowerShell 等价命令：`New-Item download\downloads,download\previews,download\watch -ItemType Directory -Force`

## 节点 A（下载节点）

1) 设置环境变量（确保两个节点使用相同 `API_TOKEN`）

Linux/macOS（在仓库根目录）：
```bash
export API_TOKEN=CHANGE_ME
# 可选：Bitmagnet（如需启用 /search）
export BITMAGNET_DB_HOST=127.0.0.1
export BITMAGNET_DB_PORT=5432
export BITMAGNET_DB_USER=postgres
export BITMAGNET_DB_PASS=postgres
```

Windows PowerShell：
```powershell
$env:API_TOKEN = 'CHANGE_ME'
# 可选：Bitmagnet
$env:BITMAGNET_DB_HOST='127.0.0.1'
$env:BITMAGNET_DB_PORT='5432'
$env:BITMAGNET_DB_USER='postgres'
$env:BITMAGNET_DB_PASS='postgres'
```

2) 启动服务（在仓库根目录执行）
```bash
docker compose -f download/docker-compose.yml up -d
```

3) 验证服务
- Transmission Web UI: `http://<下载节点IP>:9091`
- 管理页与预览墙: `http://<下载节点IP>:28000/admin/`
- 搜索页（可选 Bitmagnet）: `http://<下载节点IP>:28000/admin/search.html`

默认/可覆盖的关键环境变量：
- `DOWNLOAD_ROOT=/downloads`
- `PREVIEW_ROOT=/previews`
- `DB_PATH=/app/seedbox.db`
- `ADMIN_DIR=/frontend`

## 节点 B（处理节点）

处理节点需要：
- 能访问下载节点 API（`API_URL` 指向下载节点的 `http://<IP>:28000`）。
- 能读到下载节点给出的“视频绝对路径”。推荐两台机器共享同一存储，并在宿主机上将共享路径分别挂载到一致目录，再在容器内映射到一致路径（如都映射为 `/downloads`）。
- 提供 FFmpeg 可执行文件（默认 `python:3.11-alpine` 镜像不包含 FFmpeg）。

两种部署方式（任选其一）：

A. 容器方式（推荐，构建带 FFmpeg 的镜像）

在 `worker` 目录下创建临时镜像（示例 Dockerfile）：
```Dockerfile
FROM python:3.11-alpine
RUN apk add --no-cache ffmpeg
WORKDIR /app
COPY . /app
RUN pip install -r requirements.txt
CMD ["python", "worker.py"]
```

构建并启动（仓库根目录）：
```bash
cd worker
docker build -t seedbox-worker:ffmpeg .
cd ..
API_URL=http://<下载节点IP>:28000 \
API_TOKEN=CHANGE_ME \
docker compose -f worker/docker-compose.yml up -d
```

将 `worker/docker-compose.yml` 中 `image` 改为 `seedbox-worker:ffmpeg` 可持久化这一选择；或在现有 `image` 基础上临时安装 FFmpeg（不重启即有效）：
```bash
docker compose -f worker/docker-compose.yml run --rm worker sh -lc "apk add --no-cache ffmpeg"
```

B. 直接在宿主机运行（需在宿主机安装 FFmpeg）
```bash
cd worker
pip install -r requirements.txt
API_URL=http://<下载节点IP>:28000 API_TOKEN=CHANGE_ME python worker.py
```

环境变量：
- `API_URL`（默认 `http://localhost:28000`）
- `API_TOKEN`（必须，与下载节点一致）

挂载共享下载目录（重要）：

无论采用 A 还是 B，处理节点容器若需要直接读取视频文件，必须把与下载节点一致的“宿主机共享路径”挂载进容器并映射为相同的容器路径（一般为 `/downloads`）。示例（修改 `worker/docker-compose.yml`）：

```yaml
services:
  worker:
    image: seedbox-worker:ffmpeg   # 或 python:3.11-alpine 按上文安装 ffmpeg
    working_dir: /app
    volumes:
      - ./:/app
      - /srv/seedbox/downloads:/downloads   # 将宿主机共享路径挂载为 /downloads
    environment:
      - API_URL=${API_URL:-http://<下载节点IP>:28000}
      - API_TOKEN=${API_TOKEN:-token}
```

同时，下载节点也应把相同的宿主机路径挂载为 `/downloads`（修改 `download/docker-compose.yml`）：

```yaml
  api:
    volumes:
      - /srv/seedbox/downloads:/downloads
      - /srv/seedbox/previews:/previews
      - ../frontend:/frontend
  transmission:
    volumes:
      - /srv/seedbox/downloads:/downloads
      - ./watch:/watch
```

## 首次联调与验证

1) 在共享的下载目录放置一个测试视频（例如 `/downloads/demo.mp4`）。
2) 在“下载节点”上注册该文件到系统（使用 API 或管理页）：
```bash
curl -H "X-Auth: CHANGE_ME" -H "Content-Type: application/json" \
  -d '{"path":"/downloads/demo.mp4", "title":"Demo"}' \
  http://<下载节点IP>:28000/tasks/fetch
```
3) 观察“处理节点”日志，FFmpeg 会生成拼图并回传；条目状态变为 `ready`。
4) 打开 `http://<下载节点IP>:28000/admin/` 查看预览墙是否出现该条目与拼图。

## 常见问题（FAQ）

- 401 Unauthorized：请求未携带或携带了错误的 `X-Auth`；请在前端页面保存 Token，或在 `curl`/Worker 环境变量中设置正确的 `API_TOKEN`。
- 204 No Content（Worker 轮询）：当前没有可处理的任务，属于正常现象。
- `ffmpeg: not found`：为 Worker 提供 FFmpeg（参考“节点 B”两种方案）。
- 路径不存在/无法读取：确保两个节点共享同一下载目录，并在容器内映射到一致路径（例如都映射为 `/downloads`）。
- Bitmagnet 搜索不可用：未配置 Postgres 连接，设置 `BITMAGNET_DB_*` 后重启下载节点。

## 开发与测试

- 下载节点（Go API）：
```bash
cd download
API_TOKEN=dev go run main.go
```

- 处理节点（Python）：
```bash
cd worker
pip install -r requirements.txt
API_TOKEN=dev python worker.py
```

测试：
```bash
pytest
```

## 合规与许可

仅处理自有或已获授权的媒体内容。严禁用于任何非法用途。
