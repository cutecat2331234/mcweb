# McWeb Connector 插件

Kotlin/Java 多模块 Gradle 工程，支持 Bukkit（1.8 legacy + 1.13+ modern）、BungeeCord、Velocity。

## 构建

```bash
cd plugins/mcweb-connector
./gradlew build   # Windows: gradlew.bat build
```

产物位于各子模块 `build/libs/`：

| 模块 | 适用环境 |
|------|----------|
| `mcweb-connector-bukkit-legacy` | Spigot/Paper 1.8 – 1.12 |
| `mcweb-connector-bukkit-modern` | Paper/Spigot 1.13+ |
| `mcweb-connector-bungee` | BungeeCord 代理 |
| `mcweb-connector-velocity` | Velocity 3.x 代理 |

## 配置

在 `config.yml` 中设置：

- `website-url` — McWeb 站点地址（直连 Rails）或本地 mcweb-node 代理地址（如 `http://127.0.0.1:9876`，见 [`NODE_PROTOCOL.md`](../../NODE_PROTOCOL.md)）
- `server-id` — 后台 Minecraft 服务器 public_id
- `connector-secret` — Connector 密钥

后台 **Minecraft 设置** 可通过 `GET /config` 下发绑定命令别名、消息模板与桥接白名单。

## 命令

- `/website link` — 生成网站绑定码
- `/website whois [玩家]` — 查询网站用户名与信任等级
- `/website reload` — 重载远程配置

## 桥接

软依赖 PlaceholderAPI、LuckPerms、Vault，通过反射采集数据上报 `profile_fields` / `permission_groups` / `events`。

## 网络重试

`ConnectorClient` 对不稳定网络自动重试至少 3 次（指数退避）。

## 协议

详见仓库根目录 [`CONNECTOR_PROTOCOL.md`](../../CONNECTOR_PROTOCOL.md)。
