# Node 协议 v2

McWeb 宿主机管理节点（`mcweb-node`）与 Rails 控制面的通信协议。

## 认证

每个请求需携带（算法与 Connector 相同）：

- `X-Node-Signature`: HMAC-SHA256(node_secret, "#{timestamp}.#{body}")
- `X-Node-Timestamp`: Unix 时间戳（±5 分钟有效）

### 首次配对（无密钥时）

1. 管理员在后台节点详情点击 **生成配对令牌**
2. 在节点主机运行 `mcweb-node pair --token <token> --rails-url <url>`。远程地址默认必须为 HTTPS；仅可信内网可显式增加 `--allow-insecure-http`
3. `POST /minecraft/nodes/pair` 返回 `node_id` 与 `node_secret`（一次性）

配对成功后凭据写入 `--config` 指定的配置文件（默认 `config/mcweb-node.yml`），节点密钥不会输出到终端。

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/minecraft/nodes/pair` | 一次性配对（`pairing_token`, `hostname`） |
| POST | `/minecraft/nodes/:node_id/heartbeat` | 节点心跳 + 拉取所管实例配置 |
| GET | `/minecraft/nodes/:node_id/operations/next` | 领取一个任务团批次；已有活动批次时返回 `null` |
| POST | `/minecraft/nodes/:node_id/operations/:id/lease` | 续约正在执行的任务团批次 |
| POST | `/minecraft/nodes/:node_id/operations/:id/complete` | 一次性提交批次内所有目标结果，取得确认编号 |
| POST | `/minecraft/nodes/:node_id/operations/:id/acknowledge` | 回执确认编号；完成后该节点才可领取下一批次 |
| GET | `/minecraft/nodes/:node_id/tasks` | 拉取待执行节点任务 |
| GET | `/minecraft/nodes/:node_id/events` | 即时轮询（非阻塞）拉取紧急任务信号，有则返回 JSON 否则 `204`（见下文「紧急任务推送」） |
| POST | `/minecraft/nodes/:node_id/tasks/:id/complete` | 回报任务执行结果 |
| POST | `/minecraft/nodes/:node_id/instances/:server_id/report` | 上报实例进程状态 / 指标 |
| GET | `/minecraft/sync/:token` | 签名 URL 文件下载（`sync_files` 任务用） |

`tasks` 是 v1 兼容端点，也已限制为每次一个任务且不会自动重放超时命令。新的批量工作必须使用 v2 任务团。

## Sidekiq 任务团

Rails/Sidekiq 是远程节点工作的唯一编排者。一个“任务”是一个有明确目标快照和完成条件的父任务团，而不是 Rails 向每台 Minecraft 服务器分别发送一条命令。

例如“把插件版本 `v2` 更新到全部子服务器”会形成：

1. 一个 `NodeOperation` 父任务团，冻结本次涉及的全部服务器；
2. 每个物理 `mcweb-node` 一个批次；
3. 每个批次包含该节点负责的全部目标服务器；
4. Go 节点在本地逐项执行并持久化每个目标的成功或结构化错误；
5. 所有物理节点批次均完成后，父任务团才成为 `completed` 或 `completed_with_errors`。

同一个 Go 节点在任意时刻只能有一个活动批次。状态和握手如下：

```text
ready -> dispatched -> running -> result_pending_ack
                                      |
                                      v
                              explicit acknowledge
                                      |
                                      v
                    completed / completed_with_errors
```

Go 节点必须先把活动批次及逐目标结果写入本地账本。`complete` 失败时反复提交同一结果；收到 `acknowledgement_id` 后再调用 `acknowledge`。只有 `acknowledge` 得到 Rails 的肯定响应，节点才清除本地账本并领取下一批次。这样即使网络中断，也不会因为“领取超时”而盲目重复破坏性操作。

任务团使用字符串 `id`，避免 Rails bigint 经过 JSON 数字传给 Go 时产生精度损失。`delivery_id`、`payload_digest` 和结果摘要共同提供幂等与冲突检测。

### 当前 v2 任务类型

| operation_type | 完成条件 |
|---|---|
| `collect_metrics` | 批次内每台目标服务器均返回指标或结构化错误 |
| `sync_files` | 每台目标服务器完成原生 Go 下载、SHA-256 校验、原子替换并返回预期 revision，或返回结构化错误 |

心跳通过 `metadata.node_protocol_versions` 与 `metadata.operation_types` 上报能力。滚动升级期间，未声明 v2 的旧节点继续使用 v1；声明 v2 后自动加入任务团，避免 Rails 把新协议任务发给旧二进制。

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

v1 任务幂等：`delivery_id` 全局唯一。v2 批次还要求 `payload_digest` 一致，并记录每个目标的独立结果。

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

### nssm（Windows）

```json
{ "service": "McWeb-Survival", "nssm_path": "C:\\nssm\\nssm.exe" }
```

`nssm_path` 可选，默认在 PATH 中查找 `nssm`。

## 紧急任务推送

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/minecraft/nodes/:node_id/events?since=ISO8601` | 即时轮询（非阻塞）；有 urgent 任务时返回 JSON `{ event, wake_at }`，否则 `204 No Content` |

`stop_instance` 与 `restart_instance` 任务为 `urgent` 优先级，入队时更新 `tasks_wake_at`。心跳响应字段：`urgent_tasks_pending`、`tasks_wake_at`。

## 节点本地 spool 与任务团账本

配置 `spool_dir`（默认 `./spool`）。任务完成 POST 失败时写入 JSON，下次 tick 重放后删除。

v2 活动任务团存入 `spool_dir/operations/active-operation.json`。同一时间只允许这一份活动账本；每完成一个目标即刷新账本，进程重启后跳过已有终态结果并继续其余目标。结果确认前不会拉取任何新任务。

## 计划任务（Sidekiq Cron）

| Job | 默认频率 | 说明 |
|-----|----------|------|
| `ScheduleCollectMetricsJob` | 每 10 分钟 | 为所有托管服务器入队 `collect_metrics` |
| `ScheduledServerRestartJob` | 每 15 分钟 | 检查服务器 `metadata.restart_schedule` cron |
| `ScheduledBackupWorldJob` | 每 30 分钟 | 检查 `backup_enabled` / `backup_schedule` |

## 审计日志

以下操作写入 `audit_logs`：`minecraft.server.start/stop/restart/exec/console/backup/restore/sync_files/rotate_secret`、`minecraft.player.kick`。
