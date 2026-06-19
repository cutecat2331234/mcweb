# Connector 协议 v2

## 认证

每个请求需携带：

- `X-Connector-Signature`: HMAC-SHA256(secret, "#{timestamp}.#{body}")
- `X-Connector-Timestamp`: Unix 时间戳（±5 分钟有效）

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/minecraft/connector/:server_id/heartbeat` | 心跳 + 服务器快照（TPS/内存/插件/世界） |
| POST | `/minecraft/connector/:server_id/server_stats` | 详细服务器统计 |
| POST | `/minecraft/connector/:server_id/link_codes` | 游戏内生成绑定码 |
| POST | `/minecraft/connector/:server_id/presence` | 玩家上线/下线/换服 |
| POST | `/minecraft/connector/:server_id/profile_fields` | 批量 upsert 资料字段 |
| POST | `/minecraft/connector/:server_id/permission_groups` | 同步游戏权限组 |
| POST | `/minecraft/connector/:server_id/whois` | 查询玩家网站绑定与信任等级 |
| GET | `/minecraft/connector/:server_id/config` | 拉取后台配置 |
| POST | `/minecraft/connector/:server_id/events` | 通用事件上报 |
| GET | `/minecraft/connector/:server_id/tasks` | 拉取待执行任务 |
| POST | `/minecraft/connector/:server_id/tasks/:id/complete` | 回报执行结果 |

## 玩家标识

请求可携带：

- `player_id`（canonical，推荐）
- 或 `uuid` + `platform`（向后兼容）

响应始终包含 `player_id`（若可解析）。

## 账号绑定

1. 游戏内执行绑定命令（默认 `/website link`，可在后台 **Minecraft 设置** 配置 `link_command`）→ `POST link_codes`
2. 玩家在网站 `/app/minecraft/link` 输入验证码
3. 绑定 UUID，验证码一次性使用

### 可配置命令

`GET config` 响应包含：

| 字段 | 说明 |
|------|------|
| `link_command` | 完整命令，如 `/mcweb bind` |
| `command_root` | 主命令名（无 `/`），如 `mcweb` |
| `link_subcommand` | 绑定子命令，如 `bind` |

插件在拉取配置后会：

- 将 `command_root` 注册为 `/website` 的别名（Bukkit `PluginCommand#setAliases`；Velocity/Bungee 启动时注册）
- 将 `link_subcommand` 与 `link` 均视为触发绑定

## 发货幂等

- 每个发货任务携带全局唯一 `delivery_id`
- 插件本地持久化已处理的 `delivery_id`
- 重复任务返回已处理状态，不重复执行

## 集成事件

插件在玩家上线/下线/首次加入时调用 `POST events`（与 `presence` 并行）。

`POST events` body 示例：

```json
{
  "event": "player.first_join",
  "event_id": "unique-id",
  "payload": { "uuid": "...", "player_id": "...", "playtime_hours": 12 }
}
```

后台 `minecraft_integration_actions` 规则可触发：写资料字段、发通知、授徽章、`enqueue_connector_task` 反向任务等。

`events` 请求体顶层可同时携带 `uuid`、`username`、`platform`、`player_id`（除 `payload` 外），便于集成动作解析玩家。

## 代理端（BungeeCord / Velocity）

代理插件与 Bukkit 共享 common 模块，支持：

- `link` / `whois` / `reload` 命令（默认 `/website`，别名 `mcweb`）
- 玩家登录/下线 → `presence` + `events`
- LuckPerms 权限组同步（若代理安装 LuckPerms）
- `broadcast_announcement`、`run_commands` / `deliver_item` 任务
- 心跳上报在线人数、内存占用

Bukkit 端额外支持：皮肤纹理、`profile_fields` 桥接（PlaceholderAPI/Vault）、TPS 上报。
