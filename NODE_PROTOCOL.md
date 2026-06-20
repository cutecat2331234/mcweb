# Node 协议 v1

McWeb 宿主机管理节点（`mcweb-node`）与 Rails 控制面的通信协议。

## 认证

每个请求需携带（算法与 Connector 相同）：

- `X-Node-Signature`: HMAC-SHA256(node_secret, "#{timestamp}.#{body}")
- `X-Node-Timestamp`: Unix 时间戳（±5 分钟有效）

### 首次配对（无密钥时）

1. 管理员在后台节点详情点击 **生成配对令牌**
2. 在节点主机运行 `mcweb-node pair --token <token> --rails-url <url>`
3. `POST /minecraft/nodes/pair` 返回 `node_id` 与 `node_secret`（一次性）

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/minecraft/nodes/pair` | 一次性配对（`pairing_token`, `hostname`） |
| POST | `/minecraft/nodes/:node_id/heartbeat` | 节点心跳 + 拉取所管实例配置 |
| GET | `/minecraft/nodes/:node_id/tasks` | 拉取待执行节点任务 |
| POST | `/minecraft/nodes/:node_id/tasks/:id/complete` | 回报任务执行结果 |
| POST | `/minecraft/nodes/:node_id/instances/:server_id/report` | 上报实例进程状态 / 指标 |
| GET | `/minecraft/sync/:token` | 签名 URL 文件下载（`sync_files` 任务用） |

## Connector 透明代理（Go 本地）

节点在本地监听（默认 `http://127.0.0.1:9876`），将 `/minecraft/connector/*` 原样转发至 Rails，保留 `X-Connector-Signature` 与 `X-Connector-Timestamp`。插件在 `connection_mode=node` 时将 `website-url` 指向该地址。代理错误会记录 `server_id` 与路径。

## 节点任务类型

| task_type | 说明 |
|-----------|------|
| `start_instance` | 启动 MC 实例（需 `server_id`） |
| `stop_instance` | 停止实例（可选 `timeout_seconds`） |
| `restart_instance` | 重启实例 |
| `exec_command` | 执行 shell（`command`, `timeout`, `cwd`）— Rails 侧可配置允许前缀 |
| `collect_metrics` | 采集主机与实例指标；心跳亦上报主机指标 |
| `tail_logs` | 读取日志尾部（`path`, `lines`） |
| `backup_world` | 打包世界目录（`source` 相对路径, `destination` 绝对路径 `.tar.gz`） |
| `restore_world` | 解压世界备份（`archive`, `target` 相对目录） |
| `sync_files` | 从签名 URL 下载文件到 `destination`（插件/jar 部署） |

任务幂等：`delivery_id` 全局唯一。

## 游戏内控制台（非 Node 任务）

管理员在服务器详情发送 **控制台命令** 时，Rails 创建 Connector `run_commands` 任务（需 Connector 在线），适用于 `say`、`kick` 等游戏命令。

## heartbeat 响应

```json
{
  "node_id": "node_xxx",
  "status": "ok",
  "instances": [
    {
      "server_id": "srv_xxx",
      "name": "Survival",
      "process_driver": "systemd",
      "process_config": { "unit": "mc-survival.service" },
      "process_state": "running",
      "working_directory": "/opt/mc/survival",
      "connection_mode": "node",
      "proxy_listen_url": "http://127.0.0.1:9876"
    }
  ]
}
```

心跳 `metadata.host_metrics` 字段：`cpu_percent`, `mem_used_bytes`, `mem_total_bytes`, `disk_used_bytes`, `disk_total_bytes`。Rails 写入 `minecraft_node_metric_snapshots` 供管理后台图表使用。

## 进程 driver 配置

### systemd

```json
{ "unit": "mcweb-survival.service" }
```

### docker

```json
{ "compose_file": "/opt/mc/survival/docker-compose.yml", "service": "minecraft" }
```

### script

```json
{ "start": "./start.sh", "stop": "./stop.sh", "status": "./status.sh" }
```

## 计划任务（Sidekiq Cron）

| Job | 默认频率 | 说明 |
|-----|----------|------|
| `ScheduleCollectMetricsJob` | 每 10 分钟 | 为所有托管服务器入队 `collect_metrics` |
| `ScheduledServerRestartJob` | 每 15 分钟 | 检查服务器 `metadata.restart_schedule` cron |
| `ScheduledBackupWorldJob` | 每 30 分钟 | 检查 `backup_enabled` / `backup_schedule` |

## 审计日志

以下操作写入 `audit_logs`：`minecraft.server.start/stop/restart/exec/console/backup/restore/sync_files/rotate_secret`、`minecraft.player.kick`。
