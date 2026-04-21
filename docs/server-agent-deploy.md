# ClawPanel 服务器部署操作手册

本文面向“在服务器上执行命令的 agent / 运维脚本”，目标是让执行方按固定步骤完成部署、检查、升级和回滚。

## 目标

本仓库推荐的标准部署形态：

- **单容器 Fullstack 方案（推荐）**：`docker-compose.fullstack.yml`
  - 一个容器内运行 `ClawPanel + OpenClaw Gateway`
  - Hermes 预装但 **不启动**（`AUTO_START_HERMES_GATEWAY=0`）
  - 原因：ClawPanel 对 Hermes 集成支持不完善，启用后体验不佳

- **两容器方案（备选）**：`docker-compose.two-containers.yml`（仅供参考，不推荐新部署）
  - 如非特殊要求，建议使用单容器方案

**默认使用单容器 Fullstack 方案**

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

如果服务器启用了防火墙，还应确认以下端口允许访问：

- `1420/tcp` for ClawPanel
- `18789/tcp` for OpenClaw Gateway

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
AUTO_START_OPENCLAW_GATEWAY=1
AUTO_START_HERMES_GATEWAY=0   # 保持关闭，Hermes 集成尚不完善
```

说明：

- `AUTO_START_HERMES_GATEWAY=0` 是默认值，Hermes 已预装但不启动
- 如需使用 Hermes，请参考独立部署方案
- `HERMES_GATEWAY_PORT` 等变量仅在 Hermes 启用时相关

## 推荐部署：单容器 Fullstack

### 启动

```bash
cd /opt/clawpanel
docker compose --env-file .env -f docker-compose.fullstack.yml up -d --build
```

### 验证

查看容器状态：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml ps
```

查看日志：

```bash
docker compose --env-file .env -f docker-compose.fullstack.yml logs -f --tail=200
```

健康检查：

```bash
curl -fsS "http://127.0.0.1:${CLAWPANEL_PORT:-1420}/" >/dev/null
curl -fsS "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/health" >/dev/null
```

对外访问入口：

- `http://<server>:1420` — ClawPanel Web
- `http://<server>:18789` — OpenClaw Gateway

> **为什么不启动 Hermes？** ClawPanel 对 Hermes 的集成支持尚不完善，启用后会出现配置入口缺失、状态显示异常等问题。当前推荐仅运行 ClawPanel + OpenClaw Gateway。

## 备选部署：两容器（仅供参考）

如果需要分离运行容器（不推荐），可使用两容器方案。执行命令时把 compose 文件替换为 `docker-compose.two-containers.yml`：

```bash
cd /opt/clawpanel
docker compose --env-file .env -f docker-compose.two-containers.yml up -d --build
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

1. **默认使用单容器 Fullstack 方案**（`docker-compose.fullstack.yml`）
2. 不要删除 `./data` 目录，除非操作者明确要求清空数据
3. 修改配置优先编辑 `.env`，不要直接硬改 compose 文件
4. 执行 `up -d --build` 后必须检查 `ps`、`logs`、HTTP 健康状态
5. 确保 `AUTO_START_HERMES_GATEWAY=0`（Hermes 预装但不启用）
6. 如果 `ClawPanel` 页面可打开但 `OpenClaw` 异常，优先检查 `18789` 端口和日志
7. 不要尝试启用 Hermes，除非明确得到特殊指示（当前 ClawPanel 对 Hermes 支持不完善）

## 最小执行清单

部署 agent 可按下面顺序执行：

```bash
cd /opt/clawpanel
test -f .env || cp .env.example .env
docker compose --env-file .env -f docker-compose.fullstack.yml up -d --build
docker compose --env-file .env -f docker-compose.fullstack.yml ps
docker compose --env-file .env -f docker-compose.fullstack.yml logs --tail=200
```

部署成功判定：

- `clawpanel-fullstack` 容器为 `Up (healthy)` 或 `Up`
- `http://127.0.0.1:1420/` 可访问（ClawPanel Web）
- `http://127.0.0.1:18789/health` 可访问（OpenClaw Gateway）
