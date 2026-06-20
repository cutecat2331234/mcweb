# McWeb 迁移与后续工作

## 节点增强（2026-06）

新增 `minecraft_node_metric_snapshots` 表存储节点/服务器指标时序。部署后运行：

```bash
cd /opt/mcweb/current
sudo -u mcweb bundle exec rails db:migrate
```

重新构建并部署 `mcweb-node` 二进制（含 `backup_world`、`restore_world`、`sync_files` 任务）。

### 配置项（SiteSetting）

| 键 | 说明 |
|----|------|
| `minecraft.graceful_stop.*` | 全局优雅停机 |
| `minecraft.exec_command.allowed_prefixes` | shell 命令白名单前缀 |
| `minecraft.commerce.pause_fulfill_during_maintenance` | 维护期间暂停自动发货 |
| `minecraft.backup.enabled` / `minecraft.backup.schedule` | 默认定时备份 |

### 服务器 metadata

| 键 | 说明 |
|----|------|
| `graceful_stop_*` | 每服优雅停机覆盖 |
| `restart_schedule` | cron 表达式，如 `0 4 * * *` |
| `backup_enabled` / `backup_schedule` | 每服备份 |
| `world_directory` | 相对世界目录，默认 `world` |

## 未来工作（未实现）

以下能力在 Phase 5 中仅作规划，尚未落地：

### Rails 离线 spool buffer

当节点长时间不可达时，将 NodeTask 暂存本地 spool 并在恢复后重放，避免任务丢失。当前依赖 PostgreSQL 持久化 + 节点轮询拉取。

### WebSocket 紧急任务推送

用 WebSocket 从 Rails 向节点推送高优先级任务（如紧急停服），替代纯 HTTP 轮询以降低延迟。

### Windows nssm 进程 driver

在 `mcweb-node` 增加 `nssm` driver，支持将 MC 实例注册为 Windows 服务。当前 Windows 节点仅支持 `script` driver 与指标采集。
