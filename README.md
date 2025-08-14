# MediaHub（Seedbox）一键部署

本项目集成了 BitMagnet、BitMagnet Next Web、qBittorrent 以及转码节点，
提供一键化的 `docker compose` 部署方案。所有路径与账号密码通过
交互式脚本自动生成，仅暴露必要的服务端口。

## 功能概览

- **BitMagnet Next Web**：提供种子检索与元数据展示界面。
- **qBittorrent**：下载引擎，完成 BT 任务。
- **API / MinIO**：供转码节点通信与存储使用。
- **FFmpeg Worker**（可选）：在独立节点执行视频切片与上传。

默认开放的宿主机端口如下，可在 `.env` 中自定义：

| 服务                | 端口 |
| ------------------- | ---- |
| BitMagnet Next Web  | 3000 |
| qBittorrent Web UI  | 8081 |
| API（转码通信）     | 8000 |
| MinIO（转码通信）   | 9000 |

## 部署步骤

1. 安装 [Docker](https://docs.docker.com/engine/install/) 与
   [Docker Compose](https://docs.docker.com/compose/install/)。
2. 克隆项目并执行部署脚本：

   ```bash
   git clone https://github.com/podcctv/seedbox.git
   cd seedbox
   bash deploy.sh
   ```

   脚本会提示填写或确认所有环境变量，并根据选择启动 `server`、`transcode`
   或两者。首次运行会自动创建所需目录及配置文件。

3. 部署完成后即可访问：

   - <http://localhost:3000> — BitMagnet Next Web
   - <http://localhost:8081> — qBittorrent

## 开发与测试

本地开发可直接执行：

```bash
docker compose up -d
```

运行测试：

```bash
pytest
```

## 许可说明

本项目仅供自有或已获授权的媒体内容使用。请勿利用本项目进行任何
未获授权的传播行为。

