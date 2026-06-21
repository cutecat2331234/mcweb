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

## 已实现（2026-06-20）

### 紧急任务推送（即时轮询）

`stop_instance` / `restart_instance` 标记为 `urgent` 优先级，并更新节点的 `tasks_wake_at`。节点每 2 秒调用 `GET /minecraft/nodes/:id/events?since=...`（即时 JSON/204，不占用长连接）；有 urgent 任务时立即拉取。心跳响应亦含 `urgent_tasks_pending` 与 `tasks_wake_at` 作为兜底。

### 节点 completion spool

`mcweb-node` 在无法向 Rails 回报任务完成时，将结果写入本地 `spool/` 目录（配置项 `spool_dir`），下次 tick 自动重放。

### Windows nssm 进程 driver

在 `mcweb-node` 增加 `nssm` driver，配置示例：`{"service": "McWeb-Survival", "nssm_path": "C:\\nssm\\nssm.exe"}`。后台服务器表单的进程 driver 选项已包含 `nssm`。

## 未来工作（未实现）

### Website::Theme 与 ZIP 模板合并

数据库 `website_themes` 仍为遗留字段，前台主题以 `Frontend::Template`（ZIP）为准。

### 插槽内 theme_asset 占位符

在 HTML 插槽中支持 `{{theme_asset:path}}` 语法，尚未实现。
