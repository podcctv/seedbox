# MediaHub（Seedbox）双端部署教程

## 项目简介

MediaHub 是一个面向自有/授权媒体内容的受控获取与展示系统。它通过只读连接 BitMagnet Next Web 的 Postgres 数据库完成元数据检索，并在双端协作下完成下载、转码、预览与展示。

### 需求概述

- **检索接口**：前端直接查询 BitMagnet 数据库，获取 BT 链接及元信息。
- **下载节点**：管理员在下载节点上发起 BT 下载任务。
- **处理节点**：下载完成的视频传输至处理节点进行 FFmpeg 切片和预览图生成，结果回传对象存储。
- **展示页面**：按演员/类型分类，详情页展示预览切片、播放链接和下载链接，可收藏或删除。
- **权限控制**：未登录用户仅能浏览预览图，登录后才可播放和管理内容；管理员可创建任务与编辑配置。
- **后台配置**：服务器 IP、端口、存储等参数均可在后台页面修改。

## 从零开始的双端部署

> 以下示例以 `serve` 节点（负责下载、展示）和 `transcode` 节点（负责转码）为例。两台机器需能够互相访问（建议在同一内网或使用 VPN）。

### 1. 准备工作

1. 在两台机器上安装 [Docker](https://docs.docker.com/engine/install/) 与 [Docker Compose](https://docs.docker.com/compose/install/).
2. 确保已部署 [BitMagnet Next Web](https://github.com/journey-ad/Bitmagnet-Next-Web)，并拥有其 Postgres 只读连接串。
3. 如果希望持久化数据，可在 `.env` 中自定义 `DATA_DIR` 指向挂载目录。

### 2. 克隆代码

1. 在两台机器上拉取代码：

    ```bash
    git clone https://github.com/podcctv/seedbox.git
    cd seedbox
    ```

2. 环境变量不再需要手动编辑，后续执行 `deploy.sh` 时会交互式填写所有配置项。

### MinIO Docker Compose 部署示例

若尚未部署 MinIO，可使用以下 `docker compose` 示例快速启动一个对象存储服务，并与上述环境变量配合使用：

```yaml
version: "3.8"
services:
  minio:
    image: minio/minio:latest
    container_name: minio
    environment:
      MINIO_ROOT_USER: CHANGE_ME
      MINIO_ROOT_PASSWORD: CHANGE_ME
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - ./minio-data:/data
```

对应的 `.env` 配置：

```bash
MINIO_ENDPOINT=http://minio:9000
MINIO_ACCESS_KEY=CHANGE_ME
MINIO_SECRET_KEY=CHANGE_ME
MINIO_BUCKET_PREVIEWS=previews
MINIO_BUCKET_HLS=hls
```

启动后可在 `http://localhost:9001` 访问控制台并创建 `previews` 与 `hls` 两个桶。

### 3. 使用部署脚本配置并启动

项目提供 `deploy.sh` 一键部署脚本，可在两端直接运行：

```bash
bash deploy.sh
```

脚本会自动拉取最新代码并引导你交互式填写所有服务配置（包含密码、路径等，直接回车即可接受默认值）。部署 `serve` 节点后会打印当前配置清单，并标出需要在 `transcode` 节点中保持一致的项。重新运行脚本即可更新并重新部署。

### 4. 手动部署 serve 节点

1. 在 serve 节点上确认 `.env` 已填写共同配置和 serve 专用变量。
2. 启动服务：

    ```bash
    docker compose -f compose.serve.yml up -d
    ```

该节点包含 Web 前端、API、Postgres、MinIO、Redis 以及 qBittorrent 下载引擎。下载完成后会通过 webhook 通知 API。

### 5. 手动部署 transcode 节点

1. 在 transcode 节点上确认 `.env` 已填写共同配置。
2. 启动服务：

    ```bash
    docker compose -f compose.transcode.yml up -d
    ```

该节点运行 FFmpeg Worker 和 rclone，负责从 serve 节点拉取下载文件，生成 HLS 切片及预览图后上传至 MinIO。

### 6. 初始化与访问

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

