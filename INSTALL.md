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

## 决策记录

- **Ruby 3.4.9 而非 4.0**：Rails 8.1 生态在 3.4.x 上最稳定；4.0 发布后将在下一版本评估升级
- **无 Docker 默认依赖**：降低服主部署门槛，使用 systemd + Caddy 原生部署
- **无 Redis 默认依赖**：Solid Queue/Cache 基于 PostgreSQL
- **PostgreSQL 18**：通过 PGDG 源安装最新稳定版，避免发行版默认版本滞后
