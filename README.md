# McWeb

面向 Minecraft 服务器运营者的开源一体化 Web 平台：在单一 Rails 应用中集成展示型官网、论坛社区、虚拟商品商城、用户中心、Minecraft 服务器联动、后台管理与宿主机运维能力。

McWeb 采用 **平台内核 + 大应用 + 插件扩展** 的分层设计，适合需要「官网 + 社区 + 商城 + 游戏内发货」完整闭环的服主自建部署，而非依赖多个 SaaS 拼凑。

---

## 目录

- [适用场景](#适用场景)
- [系统架构](#系统架构)
- [功能模块](#功能模块)
- [技术栈](#技术栈)
- [仓库结构](#仓库结构)
- [核心数据流](#核心数据流)
- [扩展与集成](#扩展与集成)
- [权限模型](#权限模型)
- [安装部署](#安装部署)
- [开发环境](#开发环境)
- [文档索引](#文档索引)
- [安全说明](#安全说明)
- [许可证](#许可证)

---

## 适用场景

| 场景 | McWeb 提供的能力 |
|------|------------------|
| 服务器品牌官网 | 区块化页面、博客文章、导航、主题、SEO、多语言内容 |
| 玩家社区 | 分区论坛、私信、审核、搜索、通知、RSS、Webhook |
| 虚拟商品销售 | 购物车、订单、优惠券、礼品卡、支付回调、自动发货 |
| 游戏内联动 | 账号绑定、资料同步、权限组映射、命令发货、集成规则 |
| 多实例运维 | 宿主机节点、进程管理、备份恢复、指标采集、控制台代理 |
| 团队运营 | RBAC 细粒度权限、按模块授权、审计日志、Sidekiq 任务监控 |

---

## 系统架构

McWeb 是 **Rails 模块化单体**（modular monolith）：各业务域以命名空间隔离（`Website`、`Community`、`Commerce`、`Minecraft` 等），共享 PostgreSQL 与 Sidekiq，通过服务层（Service Object）承载业务逻辑，Controller 保持精简。

```
┌─────────────────────────────────────────────────────────────────┐
│  平台内核（Platform）— 随发行版自带                               │
│  Identity · Website CMS · Admin 壳 · Payments · Operations      │
│  · Frontend 模板引擎 · 安装/升级 · 健康检查                        │
└─────────────────────────────────────────────────────────────────┘
         ▲ 大应用直接读写 PostgreSQL，注册路由 / Job / 权限
┌────────┴──────────┬──────────────────┬─────────────────────────┐
│ 论坛 Community    │ 商城 Commerce    │ Minecraft 联动            │
│ (大应用)          │ (大应用)         │ (大应用)                  │
└────────┬──────────┴────────┬─────────┴───────────┬──────────────┘
         │                   │                     │
         └────────── 插件扩展（Extension）──────────┘
              不改核心 Ruby 业务代码、权限与协议受限
    McWeb Connector (JVM) · mcweb-node (Go) · mcweb-hostd (Go)
    · ZIP 前台模板 · 出站 Webhook · 集成规则 · 商城子功能开关
```

应用注册表：`Mcweb::ApplicationRegistry`（`lib/mcweb/application_registry.rb`）。管理员可在 **系统 → 应用与扩展**（`/admin/system/applications`）查看三层清单与启用状态。

### 前端呈现

同一 Rails 进程内按区域使用不同 UI 技术栈：

| 区域 | 布局 / 技术 | 说明 |
|------|-------------|------|
| 官网首页 / 博客 | `WebsiteLayout.vue` | 营销风页面，支持 CMS 区块与动效 |
| 论坛 / 商城 / 账户 | `PortalLayout.vue` | Inertia + Vue 3 + shadcn-vue 功能界面 |
| 管理后台 | `AdminLayout.vue` | 侧边栏运维界面，按模块分命名空间 |
| 安装向导 | ERB（`/setup`） | 一次性初始化；亦可通过 hostd 完成 |
| Connector / Node API | JSON | Webhook、游戏服通信、节点任务，不经 Inertia |

安装向导与对外 API 保留服务端实现，不迁移至 Vue SPA。

### 后台任务

生产环境使用 **Sidekiq + Redis** 异步处理支付 Webhook、订单履约、Minecraft 发货、邮件、定时发布、Webhook 投递等。队列按优先级划分：`critical` / `payments` / `minecraft` / `mailers` / `notifications` / `media` / `maintenance`。监控 UI 位于 `/jobs`（需管理员 `admin.access` 权限）。

---

## 功能模块

### 身份与权限（Identity）

- 注册、登录、邮箱验证、密码重置、会话管理与撤销
- TOTP 二步验证（可按角色强制）
- RBAC 细粒度权限键 + 员工按模块授权（`admin_module_grants`）
- 审计日志、登录限流、IP 封禁
- 多语言 UI（`en` / `zh-CN` 等）

### 官网 CMS（Website）

- **区块化页面**：`hero`、`rich_text` 等区块类型，支持排序与多语言 `translations` JSON
- **首页策略**：存在已发布的 `page_type=home` 页面时，`/` 渲染 CMS 首页；否则回退至营销首页组件
- **博客文章**：Markdown 正文、摘要、SEO、定时发布、修订历史与恢复草稿
- **导航管理**：多级导航项，支持内链页面与外链（经 `Website::SafeLink` 校验危险协议）
- **主题**：官网主题令牌；与 ZIP 前台模板（Portal/商城皮肤）相互独立
- **Sitemap**：定时任务生成 `public/sitemap.xml`

详见 [docs/WEBSITE_CMS.md](docs/WEBSITE_CMS.md)。

### 论坛社区（Community）

对标 Discourse / XenForo 的社区能力，包括但不限于：

- **内容与互动**：分区、子分区、主题、楼层、引用、嵌套回复、Wiki、慢速模式、主题前缀/标签/标签组
- **审核与版控**：待审队列、软删除与恢复、举报闭环、用户警告/禁言/沉默、分区版主、员工私语帖
- **社交**：@提及、关注用户/分区/标签、私信（含群组）、用户拉黑/忽略、信任等级（0–4）
- **搜索**：PostgreSQL 全文检索、高级语法（`in:`、`author:`、`tag:`、`is:solved` 等）、保存搜索、RSS/OPML/Webhook
- **通知**：四级订阅级别（Watching / Tracking / Normal / 取消）、站内通知 + 可配置邮件渠道、摘要与退订
- **运营**：定时发布/归档/置顶/提升、主题指派、事件 Webhook、论坛设置后台

### 商城（Commerce）

完整的虚拟商品电商闭环：

- **商品**：多规格变体、图库、数字下载、礼品卡商品、会员类型、库存与限购、促销价、定时上下架
- **购物流程**：购物车、游客合并、优惠券/礼品卡/商店余额、结账备注与赠言、配送方式与运费（可按 `StoreFeatures` 开关）
- **订单**：创建 → 支付 → 履约 → 完成；待支付过期自动取消；订单时间线、收据 HTML/PDF、物流追踪
- **售后**：客户退款申请、后台审批/拒绝、部分退款与库存/优惠券/礼品卡/余额按比例恢复
- **运营**：评价与问答、心愿单与对比、降价/到货提醒、弃购提醒、低库存通知、订单/商品 Webhook（HMAC 签名）
- **功能开关**：`Commerce::StoreFeatures` 控制实体商品、物流、礼品包装等子能力，默认面向纯数字/游戏内发货场景

支付通过 **Payments** 抽象层对接；Provider 实现签名验证与幂等 Webhook 处理。扩展新支付渠道见 [PAYMENT_PROVIDER_GUIDE.md](PAYMENT_PROVIDER_GUIDE.md)。

### Minecraft 联动（Minecraft）

- **Connector 协议**：Java 多平台插件（Bukkit / Paper、Velocity、BungeeCord）经 HMAC 认证与 Rails 通信
- **账号绑定**：游戏内生成验证码 → 网站确认绑定 UUID
- **在线与资料**：心跳、玩家上下线、资料字段同步、权限组映射、whois 查询
- **发货任务**：订单支付后创建 Connector 任务，插件拉取 → 本地 `delivery_id` 去重 → 执行命令 → 回调完成
- **集成规则**：后台配置 `event_key` + 条件 + 动作（写资料、发通知、授徽章、反向任务等），带幂等与 effect 追踪
- **节点代理**：`mcweb-node` 在宿主机执行启停实例、备份、指标、文件同步，并可透明代理 Connector 请求
- **控制台命令**：管理员经 Connector 向游戏服发送 `say`、`kick` 等命令

协议文档：[CONNECTOR_PROTOCOL.md](CONNECTOR_PROTOCOL.md)、[NODE_PROTOCOL.md](NODE_PROTOCOL.md)。

### 运维与安装（Operations）

| 组件 | 说明 |
|------|------|
| **mcweb-hostd** | 宿主机 Web 控制台 + CLI，完成安装向导、启停服务、健康检查、版本更新 |
| **发布包安装** | `quick-install.sh` + systemd + Caddy，发布包含预编译前端与 `vendor/bundle` |
| **备份恢复** | 数据库与世界备份流程，见 [BACKUP.md](BACKUP.md)、[RESTORE.md](RESTORE.md) |
| **升级** | 版本切换与迁移，见 [UPGRADE.md](UPGRADE.md) |
| **健康检查** | `Operations::HealthChecker` 供监控与 hostd 仪表盘 |

---

## 技术栈

| 类别 | 选型 |
|------|------|
| 语言 | Ruby 3.4.x |
| 框架 | Rails 8.1.x |
| 数据库 | PostgreSQL 18 |
| 队列 / 缓存 | Sidekiq + Redis；Solid Cache；Solid Cable |
| 前端 | 官网 Inertia + Vue 3；Portal / Admin：Inertia + Vue 3 + Vite + Tailwind CSS 4 |
| 游戏服插件 | Java（Gradle 多模块） |
| 宿主机组件 | Go（`mcweb-node`、`mcweb-hostd`） |
| 加密 | Lockbox（支付密钥、Connector 密钥等） |
| 分页 | Pagy |
| PDF | Prawn |

### 支持环境

- Ubuntu LTS x86_64
- Debian Stable x86_64

亦提供 Docker 部署示例（`deploy/docker/`）。

---

## 仓库结构

```
mcweb/
├── app/
│   ├── controllers/     # 按模块命名空间：admin/, community/, commerce/, minecraft/, website/
│   ├── models/          # Website, Community, Commerce, Minecraft, Payments, Identity, ...
│   ├── services/        # 业务命令对象（*::CreateOrder, Community::CreateTopic, ...）
│   ├── jobs/            # Sidekiq 异步任务
│   └── javascript/      # Inertia 页面、Portal/Admin/Website 组件
├── config/              # 路由、Sidekiq、local.yml 示例、systemd 模板
├── db/migrate/          # 数据库迁移
├── docs/                # 专题文档（CMS、hostd、资源包贴图等）
├── host/mcweb-hostd/    # 宿主机控制台（Go）
├── nodes/mcweb-node/    # 宿主机管理节点（Go）
├── plugins/mcweb-connector/  # Minecraft 服务端插件（Java）
├── lib/mcweb/           # 应用注册表、功能开关等
├── bin/                 # install、setup、jobs、dev 等脚本
├── ARCHITECTURE.md      # 架构与数据流详解
└── INSTALL.md           # 安装步骤
```

---

## 核心数据流

### 支付 → 履约

```
用户下单 → Commerce::CreateOrder
        → Payments::Record + Provider 发起支付
        → Webhook → Payments::WebhookProcessor（签名 + 幂等）
        → Commerce::ConfirmPayment（行锁）
        → Commerce::CompleteOrderPayment
        → PostPaymentSideEffectsJob（徽章、通知等）
        → Commerce::FulfillOrderJob
              ├─ 礼品卡 / 数字下载 / 会员：同步履约
              └─ MC 命令商品：Commerce::BuildConnectorTaskPayload
                        → Minecraft::DispatchFulfillmentJob
                        → Connector 拉取任务 → 执行 → 回调
                        → Commerce::SyncOrderFulfillmentStatus → order.complete!
```

数据库唯一约束 + 状态机检查保证支付与发货双侧幂等。

### Connector 心跳与任务

```
插件 heartbeat → 更新服务器快照（TPS、在线人数等）
GET tasks      → 返回 pending 任务列表
执行本地持久化 delivery_id 去重
POST complete  → Minecraft::TaskDispatcher 更新履约状态
```

### 节点任务

```
管理员配对 mcweb-node → node_secret
heartbeat          → 拉取所管实例配置 + 上报主机指标
GET tasks / events → 拉取宿主机任务（启停、备份、sync_files 等）
POST complete      → 回报执行结果
```

更完整的模块交互说明见 [ARCHITECTURE.md](ARCHITECTURE.md)。

---

## 扩展与集成

McWeb **不支持**运行时上传任意 Ruby 插件或替换大应用；扩展边界如下：

| 扩展方式 | 能做什么 |
|----------|----------|
| **FeatureFlags** | 整体开关论坛 / 商城 / Minecraft / 博客入口 |
| **Commerce::StoreFeatures** | 商城内物流、实体商品、礼品包装等子功能 |
| **ZIP 前台模板** | Portal/商城皮肤：颜色 token、CSS、HTML 插槽 |
| **McWeb Connector** | 游戏服拉任务、上报事件、账号绑定 |
| **mcweb-node** | 宿主机进程管理、备份、指标、Connector 本地代理 |
| **出站 Webhook** | 订单生命周期、论坛事件、保存搜索匹配推送到外部系统 |
| **Minecraft 集成规则** | 条件触发预置动作（非任意 Ruby 执行） |
| **支付 Provider** | 实现 Payments 适配器接口 |

三层模型与边界详解：[docs/APPS_AND_PLUGINS.md](docs/APPS_AND_PLUGINS.md)。

---

## 权限模型

- **站点用户**：普通注册玩家；论坛信任等级控制链接、图片、私信等能力
- **员工（Staff）**：绑定 RBAC 角色；可按模块授予 `forum` / `store` / `minecraft` / `website` / `system` 后台访问
- **分区版主**：辖区内的审核、删帖、移动主题等（不等同于全站管理员）
- **权限键**：细粒度如 `website.pages.publish`、`forum.topics.move`、`store.orders.refund` 等

完整权限列表见 [PERMISSIONS.md](PERMISSIONS.md)（随版本扩充）。

---

## 安装部署

### 方式一：GitHub 发布包（推荐）

在 [Actions → Release Build](https://github.com/cutecat2331234/mcweb/actions/workflows/release.yml) 下载最新 `mcweb-*.tar.gz`，或查阅对应 `v*` Release 附件：

```bash
tar -xzf mcweb-<version>.tar.gz
cd mcweb-<version>
sudo ./quick-install.sh --fresh   # 全新服务器
# 已安装过 McWeb 时仅升级应用：
sudo ./quick-install.sh
```

发布包已包含 `vendor/bundle` 与预编译前端资源，服务器上无需再执行 `bundle install` / `npm build`。

### 方式二：宿主机控制台（mcweb-hostd）

安装 `mcweb-hostd` 后，在 Web 面板完成七步安装向导，无需访问 `/setup`。详见 [docs/HOSTD.md](docs/HOSTD.md)。

### 方式三：从源码安装

```bash
git clone https://github.com/cutecat2331234/mcweb.git
cd mcweb
git checkout main
sudo bin/install
sudo -u mcweb /opt/mcweb/current/bin/setup
sudo systemctl enable --now mcweb-web mcweb-worker caddy
```

首次访问 `https://your-domain/setup`（或 hostd 向导）完成数据库、站点信息与管理员配置。

完整步骤、目录布局与配置说明：[INSTALL.md](INSTALL.md)。

---

## 开发环境

```bash
git clone https://github.com/cutecat2331234/mcweb.git
cd mcweb
bundle install
npm ci
bin/setup-local-config   # 生成本地 config/local.yml（若不存在）
bin/rails db:prepare
bin/rails db:seed
bin/dev
```

访问 http://localhost:3000

- Windows 开发环境 Sidekiq 回退为进程内 `:async` 适配器
- Go 组件测试：`cd nodes/mcweb-node && go test ./...`
- 更多约定见 [DEVELOPMENT.md](DEVELOPMENT.md)、[CONTRIBUTING.md](CONTRIBUTING.md)

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 模块边界、缓存、队列、商城开关、数据流 |
| [INSTALL.md](INSTALL.md) | 安装、目录、初始化向导、配置 |
| [UPGRADE.md](UPGRADE.md) | 版本升级 |
| [BACKUP.md](BACKUP.md) / [RESTORE.md](RESTORE.md) | 备份与恢复 |
| [SECURITY.md](SECURITY.md) | 密钥、认证、Web 安全、依赖审计 |
| [CONNECTOR_PROTOCOL.md](CONNECTOR_PROTOCOL.md) | Minecraft 插件通信协议 |
| [NODE_PROTOCOL.md](NODE_PROTOCOL.md) | 宿主机节点协议 |
| [docs/APPS_AND_PLUGINS.md](docs/APPS_AND_PLUGINS.md) | 大应用与插件扩展边界 |
| [docs/WEBSITE_CMS.md](docs/WEBSITE_CMS.md) | 官网 CMS 使用说明 |
| [docs/HOSTD.md](docs/HOSTD.md) | 宿主机控制台 |
| [TEMPLATE_SPEC.md](TEMPLATE_SPEC.md) / [THEME_GUIDE.md](THEME_GUIDE.md) | 前台 ZIP 模板规范 |
| [PAYMENT_PROVIDER_GUIDE.md](PAYMENT_PROVIDER_GUIDE.md) | 支付适配器扩展 |
| [docs/minecraft-resource-packs.md](docs/minecraft-resource-packs.md) | 商城物品贴图与资源包 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更记录 |

---

## 安全说明

- 支付密钥、Connector 密钥、SMTP 密码等使用 **Lockbox** 加密存储；`config/local.yml` 不纳入 Git
- 生产环境须配置 HTTPS、强 `SECRET_KEY_BASE` 与 `LOCKBOX_MASTER_KEY`
- 支付 Webhook 验签 + 事件幂等；Connector / Node 请求 HMAC + 时间窗校验 + 重放防护
- 用户内容与富文本经白名单清理；上传类型与大小受限
- CSRF、CSP、安全 Cookie（HttpOnly / SameSite / Secure）

详见 [SECURITY.md](SECURITY.md)。漏洞请私下联系站点管理员，勿在公开 Issue 披露可利用细节。

---

## 许可证

MIT License — 见 [LICENSE](LICENSE)
