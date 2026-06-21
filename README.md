# McWeb

面向 Minecraft 服务器服主的开源官网系统：前后端一体的 Ruby on Rails 模块化单体应用，包含展示型官网、论坛、商城、用户中心、Minecraft 服务器联动、后台管理、安装升级与运维能力。

## 功能

- **身份系统**：注册、登录、邮箱验证、密码重置、会话管理、TOTP 二步验证、RBAC 细粒度权限、审计日志
- **官网**：区块化页面构建、主题令牌、新闻公告、SEO、动画隔离
- **论坛**：分区、主题、楼层、搜索、举报审核、禁言
- **商城**：虚拟商品、订单、优惠券、支付适配器（含 Fake Provider）、幂等回调、发货
- **Minecraft Connector**：账号绑定、任务拉取、幂等发货协议
- **运维**：原生安装脚本、systemd、Caddy、备份恢复、健康检查

## 技术栈

| 类别 | 选型 |
|------|------|
| 语言 | Ruby 3.4.9（规范要求 Ruby 4.0.x，当前生态以 3.4.x 为稳定选择） |
| 框架 | Rails 8.1.x |
| 数据库 | PostgreSQL 18 |
| 队列/缓存 | Sidekiq + Redis（任务队列）、Solid Cache、Solid Cable |
| 前端 | 官网 ERB/Hotwire；业务 Portal 与管理后台 Inertia + Vue 3 + Vite + Tailwind CSS 4 |

## 支持环境

- Ubuntu LTS x86_64
- Debian Stable x86_64

## 快速安装

### 方式一：GitHub 发布包（推荐）

在 [Actions → Release Build](https://github.com/cutecat2331234/mcweb/actions/workflows/release.yml) 下载最新 `mcweb-*.tar.gz` 产物，或打 `v*` 标签自动附带到 Release：

```bash
tar -xzf mcweb-<version>.tar.gz
cd mcweb-<version>
sudo ./quick-install.sh --fresh   # 全新服务器
# 或已装过 McWeb：
sudo ./quick-install.sh           # 仅升级应用
```

发布包已包含 `vendor/bundle`、预编译前端资源，无需在服务器上 `bundle install` / `npm build`。

### 方式二：从源码安装

```bash
git clone https://github.com/cutecat2331234/mcweb.git
cd mcweb
git checkout main
sudo bin/install
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker caddy
```

首次访问 `https://your-domain/setup` 完成初始化向导。

详细说明见 [INSTALL.md](INSTALL.md)。

## 开发环境

基于 **main** 分支开发：

```bash
git clone https://github.com/cutecat2331234/mcweb.git
cd mcweb
git checkout main
bundle install
npm ci
bin/setup-local-config   # 生成本地 config/local.yml（若不存在）
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

访问 http://localhost:3000

## 安全说明

- 支付密钥与 Connector 密钥使用 Lockbox 加密存储
- 生产环境必须配置 HTTPS、强 `SECRET_KEY_BASE` 与 `LOCKBOX_MASTER_KEY`
- 详见 [SECURITY.md](SECURITY.md)

## 许可证

MIT License — 见 [LICENSE](LICENSE)

## 当前限制（v0.1.0）

- 支付适配器首版仅完整实现 Fake Provider，支付宝/微信/Stripe 为扩展骨架
- Minecraft Connector 提供完整 Java 多平台插件（Bukkit / Velocity / Bungee）；节点代理为 Go 版 `mcweb-node`
- 多语言 UI 部分完成，数据结构已支持翻译字段
