# MediaHub（Seedbox）双机部署指南

## 项目简介

MediaHub 是一个面向自有/授权媒体内容的受控获取与展示系统。它通过只读连接 BitMagnet Next Web 的 Postgres 数据库完成元数据检索，并在双机协作下完成下载、转码、预览与展示。

### 需求概述

- **检索接口**：前端直接查询 BitMagnet 数据库，获取 BT 链接及元信息。
- **下载节点**：管理员在下载节点上发起 BT 下载任务。
- **处理节点**：下载完成的视频传输至处理节点进行 FFmpeg 切片和预览图生成，结果回传对象存储。
- **展示页面**：按演员/类型分类，详情页展示预览切片、播放链接和下载链接，可收藏或删除。
- **权限控制**：未登录用户仅能浏览预览图，登录后才可播放和管理内容；管理员可创建任务与编辑配置。
- **后台配置**：服务器 IP、端口、存储等参数均可在后台页面修改。

## 从零开始的双机部署

> 以下示例以 `serve` 节点（负责下载、展示）和 `transcode` 节点（负责转码）为例。两台机器需能够互相访问（建议在同一内网或使用 VPN）。

### 1. 准备工作

1. 在两台机器上安装 [Docker](https://docs.docker.com/engine/install/) 与 [Docker Compose](https://docs.docker.com/compose/install/).
2. 确保已部署 [BitMagnet Next Web](https://github.com/journey-ad/Bitmagnet-Next-Web)，并拥有其 Postgres 只读连接串。

### 2. 克隆代码并配置环境变量

1. 在两台机器上拉取代码并复制环境变量模板：

    ```bash
    git clone https://github.com/your-org/seedbox.git
    cd seedbox
    cp .env.example .env
    ```

2. 根据节点类型编辑 `.env`：

    - **共同配置**（两台机器都需要）
      - `MINIO_ENDPOINT`、`MINIO_ACCESS_KEY`、`MINIO_SECRET_KEY`、`MINIO_BUCKET_PREVIEWS`、`MINIO_BUCKET_HLS`：对象存储 MinIO 信息。
    - **serve 节点专用**（仅在下载/展示节点填写）
      - `APP_DB_NAME`、`APP_DB_USER`、`APP_DB_PASS`、`APP_DB_HOST`、`APP_DB_PORT`：内部数据库。
      - `BITMAGNET_RO_DSN`：BitMagnet 只读数据库 DSN。
      - `REDIS_URL`：Redis 缓存地址。
      - `JWT_SECRET`、`JWT_EXP_HOURS`：JWT 鉴权参数。
      - `QBT_BASEURL`、`QBT_USER`、`QBT_PASS`：qBittorrent 下载服务。
      - `API_PUBLIC_BASE`、`WEB_PUBLIC_BASE`：对外访问域名或 IP。
    - **transcode 节点专用**
      - 目前无额外变量，确保已填写以上共同配置。

### 3. 部署 serve 节点

1. 在 serve 节点上确认 `.env` 已填写共同配置和 serve 专用变量。
2. 启动服务：

    ```bash
    docker compose -f compose.serve.yml up -d
    ```

该节点包含 Web 前端、API、Postgres、MinIO、Redis 以及 qBittorrent 下载引擎。下载完成后会通过 webhook 通知 API。

### 4. 部署 transcode 节点

1. 在 transcode 节点上确认 `.env` 已填写共同配置。
2. 启动服务：

    ```bash
    docker compose -f compose.transcode.yml up -d
    ```

该节点运行 FFmpeg Worker 和 rclone，负责从 serve 节点拉取下载文件，生成 HLS 切片及预览图后上传至 MinIO。

### 5. 初始化与访问

1. 首次启动后，通过后台管理页面完成服务器地址、对象存储、下载引擎等配置。
2. 访问 `https://<WEB_PUBLIC_BASE>`，默认仅能查看预览图。登录后可播放、收藏或删除。
3. 管理员可在搜索页使用 BitMagnet 数据创建下载任务，完成后即可在详情页查看预览切片并播放。

## 开发与测试

本地开发可直接运行：

```bash
docker compose up -d
```

运行测试：

```bash
pytest
```

## 许可

本项目仅处理自有或已获授权的媒体内容。任何未经授权的分发与公开索引均被禁止。

