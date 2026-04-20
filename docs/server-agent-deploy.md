# ClawPanel 服务器部署操作手册

本文面向“在服务器上执行命令的 agent / 运维脚本”，目标是让执行方按固定步骤完成部署、检查、升级和回滚。

## 目标

本仓库提供两种推荐部署形态：

1. `docker-compose.fullstack.yml`
   一个容器内运行 `ClawPanel + OpenClaw + Hermes`
2. `docker-compose.two-containers.yml`
   两个容器运行：
   `clawpanel + openclaw`
   `hermes`

如果没有明确要求，优先使用“两容器”方案。

原因：

- `ClawPanel` 与 `OpenClaw` 当前实现耦合较深，放在同一容器更稳
- `Hermes` 支持独立 Gateway URL，更适合拆分
- 仍然暴露 `ClawPanel` 和 `OpenClaw` 两个端口，满足外部访问和调试

## 目录约定

假设部署目录为：

```bash
/opt/clawpanel
```

执行前确保该目录下包含以下文件：

- `Dockerfile.fullstack`
- `Dockerfile.hermes`
- `docker-compose.fullstack.yml`
- `docker-compose.two-containers.yml`
- `.env` 或 `.env.example`

## 前置检查

执行 agent 在部署前应完成以下检查：

```bash
docker --version
docker compose version
```

确认：

- Docker Engine 可用
- `docker compose` 子命令可用
- 当前用户有权执行 Docker

如果服务器启用了防火墙，还应确认预期端口允许访问：

- `1420/tcp` for ClawPanel
- `18789/tcp` for OpenClaw Gateway
- `8642/tcp` for Hermes Gateway（如果需要外部访问）

## 环境变量文件

首次部署时：

```bash
cd /opt/clawpanel
cp .env.example .env
```

然后编辑 `.env`，至少确认这些值：

```dotenv
CLAWPANEL_PORT=1420
OPENCLAW_GATEWAY_PORT=18789
HERMES_GATEWAY_PORT=8642
HERMES_PROVIDER=openai
HERMES_MODEL=gpt-4o
HERMES_API_KEY=your-real-key
```

说明：

- 如果 `HERMES_API_KEY` 为空，Hermes 容器不会正常启动
- 如果你暂时不需要 Hermes，可在单容器方案中保持 `AUTO_START_HERMES_GATEWAY=0`

## 推荐部署：两容器

### 启动

```bash
cd /opt/clawpanel
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
```

### 验证

查看容器状态：

```bash
docker compose --env-file .env -f docker-compose.two-containers.yml ps
```

查看日志：

```bash
docker compose --env-file .env -f docker-compose.two-containers.yml logs -f --tail=200
```

健康检查：

```bash
curl -fsS "http://127.0.0.1:${CLAWPANEL_PORT:-1420}/" >/dev/null
curl -fsS "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/health" || true
curl -fsS "http://127.0.0.1:${HERMES_GATEWAY_PORT:-8642}/health"
```

对外访问入口：

- `http://<server>:1420`
- `http://<server>:18789`

## 备选部署：单容器

适用场景：

- 希望最少容器数量
- 不在乎一个容器内多进程
- 希望 `ClawPanel / OpenClaw / Hermes` 尽量共享本地文件环境

启动：

```bash
cd /opt/clawpanel
docker compose --env-file .env -f docker-compose.fullstack.yml up -d --build
```

查看状态：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml ps
docker compose --env-file .env -f docker-compose.fullstack.yml logs -f --tail=200
```

## 常用运维操作

### 重启

两容器：

```bash
docker compose --env-file .env -f docker-compose.two-containers.yml restart
```

单容器：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml restart
```

### 仅重建镜像并重启

两容器：

```bash
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
```

单容器：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml up -d --build
```

### 停止

两容器：

```bash
docker compose --env-file .env -f docker-compose.two-containers.yml down
```

单容器：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml down
```

注意：

- `down` 不会删除 bind mount 挂载的数据目录
- 如果数据目录在 `./data/...`，重建容器后数据仍保留

## 日志位置

宿主机 bind mount 目录默认来自 `.env`：

- `OPENCLAW_DATA_DIR`
- `HERMES_DATA_DIR`
- `HERMES_LOG_DIR`
- `PANEL_DATA_DIR`

关键文件：

- `${OPENCLAW_DATA_DIR}/openclaw.json`
- `${PANEL_DATA_DIR}/openclaw-gateway.log`
- `${HERMES_LOG_DIR}/hermes-gateway.log`
- `${OPENCLAW_DATA_DIR}/clawpanel.json`

## 升级步骤

标准升级流程：

```bash
cd /opt/clawpanel
git pull origin main
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
```

如果使用单容器，把 compose 文件名替换为：

```bash
docker-compose.fullstack.yml
```

## 回滚建议

如果升级后异常：

1. 保留当前 `./data` 目录，不要删除
2. 切回上一个 git commit 或发布 tag
3. 重新执行 `docker compose ... up -d --build`

示例：

```bash
cd /opt/clawpanel
git log --oneline -n 5
git checkout <previous-commit>
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
```

## Agent 执行准则

服务器上的 agent 按以下原则操作：

1. 默认使用两容器方案，除非操作者明确要求单容器。
2. 不要删除 `./data` 目录，除非操作者明确要求清空数据。
3. 修改配置优先编辑 `.env`，不要直接硬改 compose 文件。
4. 执行 `up -d --build` 后必须检查 `ps`、`logs`、HTTP 健康状态。
5. Hermes 未启动时，先检查 `.env` 中的 `HERMES_API_KEY` 是否为空。
6. 如果 `ClawPanel` 页面可打开但 `OpenClaw` 异常，优先检查 `18789` 端口和 `openclaw-gateway.log`。
7. 如果 `ClawPanel` 能打开但 Hermes 页面异常，优先检查 `HERMES_EXTERNAL_URL`、`8642` 端口和 `hermes-gateway.log`。

## 最小执行清单

部署 agent 可按下面顺序执行：

```bash
cd /opt/clawpanel
test -f .env || cp .env.example .env
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
docker compose --env-file .env -f docker-compose.two-containers.yml ps
docker compose --env-file .env -f docker-compose.two-containers.yml logs --tail=200
```

部署成功判定：

- `clawpanel` 容器为 `Up`
- `hermes` 容器为 `Up` 或 `healthy`
- `http://127.0.0.1:1420/` 可访问
- `http://127.0.0.1:18789/health` 或对应网关接口可访问
- `http://127.0.0.1:8642/health` 可访问
