# MediaHub Seedbox（新技术栈）

该项目采用双机协作模式：

1. **下载节点**负责 BT 下载并提供预览墙，支持条目编辑与删除。
2. **处理节点**对下载完成的视频进行切片，生成预览图后回传给下载节点。

## 架构概览

下载节点组件：

- Transmission-daemon 处理 BT 下载
- Go (Gin) API 提供编辑、删除及任务接口
- Vue 3 + Vite 前端展示预览墙
- SQLite 存储条目信息

处理节点组件：

- Python 3 脚本监听待处理目录
- FFmpeg 生成预览拼图
- 通过 HTTP 调用下载节点接口回传结果

```
[Download Node]
  ├── Transmission
  ├── Gin API
  └── Vue Preview Wall
           ↑
           │ POST /api/previews
[Worker Node]
  └── Python + FFmpeg
```

## 快速上手

1. 安装 [Docker](https://docs.docker.com/engine/install/) 与 [Docker Compose](https://docs.docker.com/compose/install/)。
2. 克隆仓库并执行部署脚本：

```bash
git clone https://github.com/podcctv/seedbox.git
cd seedbox
bash deploy.sh        # Linux / macOS
```

或在 Windows 上使用 PowerShell：

```powershell
git clone https://github.com/podcctv/seedbox.git
cd seedbox
pwsh deploy.ps1
```

### 启动下载节点

```bash
docker compose -f compose.download.yml up -d
```

访问：

- <http://localhost:3001> — 预览墙
- <http://localhost:9091> — Transmission Web UI

### 启动处理节点

```bash
docker compose -f compose.worker.yml up -d
```

处理节点自动轮询新任务并回传预览图。

## 开发模式

```bash
docker compose up -d
```

## 测试

```bash
pytest
```

## 许可说明

仅用于自有或已获授权的媒体内容，勿用于非法传播。
