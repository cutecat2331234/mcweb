# 安装指南

McWeb 支持两种安装路径：

| 路径 | 说明 |
|------|------|
| **宿主机控制台（推荐）** | 安装 [`mcweb-hostd`](docs/HOSTD.md)，在控制台内完成部署、数据库、站点与管理员配置，**无需**访问 `/setup`。 |
| **手动安装** | 按下方脚本部署后，浏览器打开 **`/setup`** 完成网页向导。 |

## 宿主机控制台（mcweb-hostd）

详见 [docs/HOSTD.md](docs/HOSTD.md)。简要步骤：

```bash
sudo install -m 755 mcweb-hostd /usr/local/bin/
sudo mkdir -p /etc/mcweb
sudo cp host/mcweb-hostd/config/hostd.example.yml /etc/mcweb/hostd.yml
sudo mcweb-hostd init
sudo systemctl enable --now mcweb-hostd
# 浏览器访问 :8787，完成 Install 向导
```

## 前置条件

- Ubuntu 22.04/24.04 或 Debian 12+ x86_64
- PostgreSQL 18（安装脚本通过官方 PGDG 源安装）
- root 或 sudo 权限
- 域名已解析到服务器（certbot 申请证书前必须先解析到本机）
- 开放 80、443 端口（80 用于 Let's Encrypt HTTP-01 校验，443 提供 HTTPS）

> HTTPS 由 **nginx + certbot（Let's Encrypt）** 自动申请并续期：安装脚本会安装
> nginx 与 certbot、部署反向代理配置、为 `MCWEB_DOMAIN` 申请证书，续期由 certbot
> 自带的 `certbot.timer` 定时任务负责，无需手动干预。域名未解析或 80 端口未放行时
> 证书申请会失败，但 HTTP 仍可用，可在就绪后重跑 `bin/install` 或手动执行 certbot。

## 发布包快速安装（推荐）

从 GitHub Actions **Release Build** 工作流下载 `mcweb-*.tar.gz`：

```bash
tar -xzf mcweb-*.tar.gz
cd mcweb-*
sha256sum -c mcweb-*.tar.gz.sha256
sudo ./quick-install.sh --fresh      # 全新安装
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker nginx
```

`quick-install.sh` 只用于全新安装。已部署服务器不得用它直接覆盖 `current`；升级时
先校验发布包并解压到新的 `/opt/mcweb/releases/<version>`，再使用下文
“安全备份、恢复与 release 更新”中的显式候选版本流程。

## 从源码交互式安装

```bash
sudo bin/install
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker nginx
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

## 安全备份、恢复与 release 更新

生产备份必须先配置灾备 OpenPGP 公钥指纹
`MCWEB_BACKUP_GPG_RECIPIENT`，或提供密钥管理系统的不可变版本引用
`MCWEB_SECRET_BACKUP_REFERENCE`。`bin/backup` 不会明文复制
`/etc/mcweb/mcweb.env`；缺少两种安全配置来源时会失败关闭。

`bin/restore` 默认只验证 manifest、SHA-256、数据库 dump 与存储清单，不执行恢复。
实际恢复必须使用 `--apply`、精确 `RESTORE:<backup-id>` 确认、明确数据库名和新建
空库；本地存储及解密配置也只能写入不存在的目标。

原生 release 更新必须先把候选包放入 `/opt/mcweb/releases/<version>`，再执行：

```bash
sudo /opt/mcweb/releases/<version>/bin/update \
  --release /opt/mcweb/releases/<version> \
  --confirm UPDATE:<version>
```

脚本会在修改 `current` 前完成候选检查、备份、迁移和旧版本回滚检查。回滚默认
`--check`，实际切换还需 `--apply --confirm ROLLBACK:<version>`。数据库 schema
不会自动向下迁移。完整步骤、OpenPGP/secret-manager 示例及真实演练清单见
[`docs/PRODUCTION_BACKUP_AND_RELEASE.md`](docs/PRODUCTION_BACKUP_AND_RELEASE.md)。

## 初始化向导

**手动安装路径**：安装后访问 `/setup`：

1. 数据库连接
2. 站点信息
3. 管理员账号
4. 完成后自动锁定安装入口

**控制台路径**：在 hostd `/install` 向导中完成上述步骤，安装锁定后 `/setup` 不可再访问。

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

升级前应备份数据库与配置，部署新版本后运行 `bundle exec rails db:migrate`。节点二进制发生变化时，应随对应版本重新构建并部署 `mcweb-node`。

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

McWeb **不会**加载项目根目录的 `local.env`。开发环境可将数据库与加密密钥写入
`config/local.yml`；生产环境优先从 systemd、容器 secret 或密钥管理系统注入的
环境变量读取，不能把发布机上的示例 `local.yml` 当作密钥来源。

## 生产公网、邮件与对象存储

生产环境启动时会校验公网边界、SMTP 和对象存储配置。示例值、HTTP 公网地址、
通配 Host、全网可信代理、本地上传盘或不完整的凭证会直接阻止 Web 与 Worker 启动，
避免服务带着不安全的 Rails 默认值上线。先复制
`config/templates/mcweb.env.example` 到 `/etc/mcweb/mcweb.env`，替换所有
`example.com` 和 `replace_with_*`，再运行 `bin/setup`。`bin/install` 首次生成
该文件时会安全暂停；编辑完成后重新运行 `bin/install`，安装程序会加载相同环境
再执行生产构建，避免构建过程绕过启动校验。

公网与代理配置：

```bash
SECRET_KEY_BASE=<bin/rails secret 生成的至少 64 字节随机值>
LOCKBOX_MASTER_KEY=<64 个十六进制字符>
RAILS_INBOUND_EMAIL_PASSWORD=<至少 32 字节随机值>
MCWEB_DATABASE_USERNAME=mcweb
MCWEB_DATABASE_PASSWORD=<数据库专用随机密码>
MCWEB_DATABASE_NAME=mcweb_production
# 本机 PostgreSQL/peer 认证可留空；容器或远程数据库填写精确主机
MCWEB_DATABASE_HOST=
MCWEB_PUBLIC_URL=https://community.your-domain.tld
MCWEB_ALLOWED_HOSTS=community.your-domain.tld
# 本机 nginx；远程负载均衡器应填写其真实私网 IP/CIDR，禁止 0.0.0.0/0 或 ::/0
MCWEB_TRUSTED_PROXIES=127.0.0.1/32,::1/128
```

生产启动会拒绝模板中的 `change_me`、`replace_with_*`、`generate_*` 以及过短或
格式错误的加密密钥。`SECRET_KEY_BASE`、Lockbox 密钥和数据库环境变量会覆盖
开发用 `config/local.yml`，Docker 模板也会先运行一次性 `mcweb-migrate` 服务，
成功完成 `db:prepare` 后才启动 Web 与 Worker。

Rails 在生产环境固定启用 HTTPS 重定向、安全 Cookie 和一年 HSTS，并只接受
`MCWEB_ALLOWED_HOSTS` 中的精确 Host。TLS 必须在 nginx 或可信负载均衡器终止，
且代理必须覆盖 `Host`、`X-Forwarded-For`、`X-Forwarded-Proto`；
不要把 Puma 端口暴露到公网。Docker 模板也只把 Puma 端口绑定到
`127.0.0.1`。

SMTP 与统一发件人：

```bash
MCWEB_SMTP_ADDRESS=smtp.your-provider.tld
MCWEB_SMTP_PORT=587
MCWEB_SMTP_AUTHENTICATION=plain
MCWEB_SMTP_USERNAME=...
MCWEB_SMTP_PASSWORD=...
MCWEB_SMTP_TLS=starttls
MCWEB_MAIL_FROM="McWeb <noreply@your-domain.tld>"
```

生产投递失败会抛出错误供任务重试和告警采集。仅可信私网邮件中继可将
`MCWEB_SMTP_AUTHENTICATION` 设为 `none` 并同时省略用户名和密码。上线前还必须
在邮件供应商配置 SPF、DKIM、DMARC、退信/投诉 Webhook 或供应商告警，并用真实
收件箱完成投递和退信演练；当前通用 SMTP 配置本身不能替代供应商侧退信监控。

上传文件必须使用私有 S3 兼容对象存储：

```bash
MCWEB_ACTIVE_STORAGE_SERVICE=private_s3
MCWEB_S3_BUCKET=mcweb-production-private
MCWEB_S3_REGION=us-east-1
MCWEB_S3_ACCESS_KEY_ID=...
MCWEB_S3_SECRET_ACCESS_KEY=...
# AWS S3 留空；MinIO、R2 等填写供应商的 HTTPS endpoint
MCWEB_S3_ENDPOINT=
MCWEB_S3_FORCE_PATH_STYLE=0
```

使用实例/工作负载 IAM role 时，可以同时省略两个静态 S3 凭证。Bucket 必须关闭
公共访问，服务账号只授予目标 bucket 所需的最小对象权限，并配置版本控制、异地
复制或供应商备份及生命周期策略。上线验收需实际完成上传、下载、删除和一次恢复
演练；仅填写环境变量不代表备份验收已经完成。

修改后先执行：

```bash
sudo systemctl restart mcweb-web mcweb-worker
sudo systemctl --no-pager --full status mcweb-web mcweb-worker
curl -fsS https://community.your-domain.tld/health/ready
```

若环境变量由 systemd、容器 secret 或密钥管理系统注入，请使用对应平台的
`exec`/健康检查方式验证，且不要把展开后的凭证打印到终端或日志。

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

- **Ruby 4.0.6**：与 Rails 8.1.3 配套使用
- **无 Docker 默认依赖**：降低服主部署门槛，使用 systemd + nginx + certbot 原生部署
- **Sidekiq + Redis 处理后台任务**：替代原 Solid Queue（PostgreSQL 队列）；`solid_cache` 仍基于 PostgreSQL，Redis 仅用于任务队列
- **PostgreSQL 18**：通过 PGDG 源安装最新稳定版，避免发行版默认版本滞后
