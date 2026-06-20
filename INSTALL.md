# 安装指南

## 前置条件

- Ubuntu 22.04/24.04 或 Debian 12+ x86_64
- PostgreSQL 18（安装脚本通过官方 PGDG 源安装）
- root 或 sudo 权限
- 域名已解析到服务器
- 开放 80、443 端口

## 发布包快速安装（推荐）

从 GitHub Actions **Release Build** 工作流下载 `mcweb-*.tar.gz`：

```bash
tar -xzf mcweb-*.tar.gz
cd mcweb-*
sha256sum -c mcweb-*.tar.gz.sha256   # 可选：校验完整性
sudo ./quick-install.sh --fresh      # 全新安装
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker caddy
```

已部署过的服务器升级：

```bash
tar -xzf mcweb-*.tar.gz && cd mcweb-*
sudo ./quick-install.sh
```

## 从源码交互式安装

```bash
sudo bin/install
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker caddy
```

## 目录结构

| 路径 | 用途 |
|------|------|
| `/opt/mcweb/releases/<version>` | 应用发布版本 |
| `/opt/mcweb/current` | 当前版本软链接 |
| `/etc/mcweb` | 配置文件 |
| `/var/lib/mcweb/uploads` | 上传文件 |
| `/var/log/mcweb` | 日志 |
| `/var/backups/mcweb` | 备份 |

## 初始化向导

安装后访问 `/setup`：

1. 站点信息
2. 管理员账号
3. 完成后自动锁定安装入口

## Minecraft Connector 插件

McWeb 提供三端 Connector 插件（Bukkit 1.8 legacy / 1.13+ modern、BungeeCord、Velocity），用于游戏内绑定账户、心跳上报、任务发货与第三方插件桥接。

### 获取插件

- **发布包**：Release Build 产物中的 `plugins/` 目录（各版本对应 jar）
- **源码构建**：

```bash
cd plugins/mcweb-connector
./gradlew build   # Windows: gradlew.bat build
```

构建产物位于各子模块 `build/libs/`。

### 后台配置

1. 登录管理后台 → **系统** → **Minecraft 服务器** → 新建服务器
2. 记录 **Server ID** 与 **Connector 密钥**（可在服务器详情页轮换密钥）
3. 在 **Minecraft 设置** 中配置绑定命令、皮肤展示模式、桥接白名单等

### 游戏端安装

将对应平台的 jar 放入 `plugins/` 目录，编辑 `plugins/McWebConnector/config.yml`：

```yaml
website-url: https://your-site.example
server-id: srv_xxxxxxxx
connector-secret: <后台显示的密钥>
```

重启服务器后执行 `/website link` 生成绑定码，在网站 `/app/minecraft/link` 完成绑定。

### 常用命令

| 命令 | 说明 |
|------|------|
| `/website link` | 生成 8 位绑定码 |
| `/website whois [玩家]` | 查询网站绑定与信任等级 |
| `/website reload` | 重载远程配置 |

协议细节见仓库根目录 [`CONNECTOR_PROTOCOL.md`](CONNECTOR_PROTOCOL.md)。

## McWeb 管理节点（mcweb-node）

宿主机 Go 代理：在绑定节点后，Connector 插件改连本地节点，由节点透明转发至 Rails，并负责启停 MC 进程、远程 shell、指标采集。协议见 [`NODE_PROTOCOL.md`](NODE_PROTOCOL.md)。

### 构建

```bash
cd nodes/mcweb-node
go build -o bin/mcweb-node ./cmd/mcweb-node
```

### 配置

复制 `nodes/mcweb-node/config/mcweb-node.example.yml` 为 `/etc/mcweb/node.yml`：

```yaml
rails_url: "https://your-site.example"
node_id: "node_xxxxxxxx"
node_secret: "<后台节点详情页轮换密钥>"
proxy_listen: "127.0.0.1:9876"
poll_interval: 10s
```

### 后台

1. **系统** → **Minecraft 节点** → 新建节点；首次部署可点击 **生成配对令牌**，在节点主机执行 `mcweb-node pair --token <token>`
2. 或轮换密钥后手动写入 `node.yml`
3. **Minecraft 服务器** → 绑定节点（新建时可采纳「负载最低节点」建议），配置 `connection_mode: node`、进程 driver（systemd/docker/script）
4. 服务器详情页：启停、游戏控制台、备份/恢复、指标图表、审计日志
5. 服务器详情页可复制推荐插件 `config.yml` 片段（`website-url` 指向 `127.0.0.1:9876`）

升级与迁移说明见 [`docs/MIGRATION.md`](docs/MIGRATION.md)。

### systemd

参考 [`config/templates/mcweb-node.service`](config/templates/mcweb-node.service) 安装为系统服务。

## 本地开发配置（config/local.yml）

实例级数据库与密钥写入 `config/local.yml`（已从 Git 忽略）。首次克隆后：

```bash
bin/setup-local-config   # 若不存在则从 server/config/database.yml 或 local.yml.example 生成
bin/local-serve            # 本地启动；无 local.yml 时会自动运行 setup-local-config
```

也可访问 `/setup` 向导填写数据库与 `secret_key_base` / `lockbox_master_key`。

`config/local.yml` 还可选填 `redis_url`、`job_concurrency`（本地 Sidekiq）；`config/boot.rb` 会在未设置环境变量时自动注入 `REDIS_URL` / `JOB_CONCURRENCY`。

与 Minecraft 同机部署时，可将 `MCWEB_SERVER_ROOT` 指向服务端根目录，以便从 `config/database.yml` 导入连接信息：

```bash
export MCWEB_SERVER_ROOT=/srv/minecraft
bin/setup-local-config
```

旧脚本 `script/setup_minecraft.rb` 仍可用但已弃用，请改用 `bin/setup-local-config`。

### local.env 说明

McWeb **不会**加载项目根目录的 `local.env`。数据库与加密密钥请使用 `config/local.yml`。生产环境 `/etc/mcweb/mcweb.env` 仅用于进程环境变量（如 `REDIS_URL`、`RAILS_ENV`），与 `local.yml` 分工明确。

## Minecraft 资源包贴图

商城可引用本机资源包/Mod 材质目录展示自定义物品图标，详见 [`docs/minecraft-resource-packs.md`](docs/minecraft-resource-packs.md)。复制 `config/image_packs.yml.example` 为 `config/image_packs.yml` 并配置各 pack 的 `root` 路径。

## 后台任务（Sidekiq + Redis）

McWeb 使用 [Sidekiq](https://sidekiq.org/) 处理异步任务与定时任务（`config/sidekiq_cron.yml`）。生产环境需要 Redis，并通过环境变量 `REDIS_URL` 连接（默认 `redis://localhost:6379/0`）。

### 启用步骤（Redis 部署可后续进行）

1. 安装并启动 Redis（或 Valkey），例如本机 `127.0.0.1:6379`
2. 在 `/etc/mcweb/mcweb.env` 中设置：

```bash
REDIS_URL=redis://127.0.0.1:6379/0
```

3. 确保 `mcweb-worker` 服务已启用（systemd 单元执行 `bundle exec sidekiq -C config/sidekiq.yml`）
4. 管理员可在 `/jobs` 查看 Sidekiq Web 监控（需登录且具有 `admin.access` 权限）

### 开发环境

- **Linux/macOS**：配置 `REDIS_URL` 后运行 `bundle exec sidekiq -C config/sidekiq.yml` 处理队列；未启动 worker 时任务会积压在 Redis 中
- **Windows**：Sidekiq worker 不支持 Windows，开发环境自动使用 `:async` 适配器（进程内执行，无 Redis 依赖）

## 决策记录

- **Ruby 3.4.9 而非 4.0**：Rails 8.1 生态在 3.4.x 上最稳定；4.0 发布后将在下一版本评估升级
- **无 Docker 默认依赖**：降低服主部署门槛，使用 systemd + Caddy 原生部署
- **Sidekiq + Redis 处理后台任务**：替代原 Solid Queue（PostgreSQL 队列）；`solid_cache` 仍基于 PostgreSQL，Redis 仅用于任务队列
- **PostgreSQL 18**：通过 PGDG 源安装最新稳定版，避免发行版默认版本滞后
