# 大应用与插件扩展

McWeb 是 **Rails 模块化单体**，不是 WordPress/Discourse 式「上传 ZIP 即可装任意 Ruby 插件」的平台。本文说明三层边界，以及当前**能扩展什么、不能扩展什么**。

## 三层模型

```
┌─────────────────────────────────────────────────────────────┐
│  平台内核（Platform）— 随发行版自带，不可卸载                  │
│  Identity · Website CMS · Admin 壳 · Payments · Operations   │
│  · Frontend 模板引擎                                          │
└─────────────────────────────────────────────────────────────┘
         ▲ 大应用直接读写 PostgreSQL、注册路由/Job/权限
┌────────┴────────┬──────────────────┬────────────────────────┐
│ 论坛 Community │ 商城 Commerce    │ Minecraft 联动          │
│ (大应用)       │ (大应用)         │ (大应用)                │
└────────┬────────┴────────┬─────────┴───────────┬───────────┘
         │                 │                     │
         └──────── 插件扩展（Extension）──────────┘
                    不改核心代码、权限受限
    McWeb Connector (JVM) · mcweb-node (Go) · ZIP 模板
    · 出站 Webhook · 集成规则 · 商城子功能开关
```

代码注册表：`Mcweb::ApplicationRegistry`（`lib/mcweb/application_registry.rb`）。

## 大应用（Application）

| ID | 模块 | 能力 | 开关 |
|----|------|------|------|
| `forum` | `Community::*` | 分区/主题/审核/私信/Webhook | `FeatureFlags` → `features.forum.enabled` |
| `store` | `Commerce::*` | 商品/订单/支付后履约/退款 | `features.store.enabled` |
| `minecraft` | `Minecraft::*` | 绑定/Connector/节点/发货任务 | `features.minecraft.enabled` |
| `website_blog` | `Website::*` | 官网博客导航入口 | `features.website_blog.enabled` |

### 大应用具备

- 独立 ActiveRecord 模型与 `db/migrate` 表
- 独立 `app/controllers`、`app/services`、`app/jobs`
- 独立 Inertia 页面与后台 `Admin::*` 命名空间
- 独立 RBAC 权限键与 `admin_module_grants`（员工按模块授权）
- 可通过 `FeatureFlags` **整体关闭前台入口**（论坛与商城至少保留一个）

### 大应用不是

- 不能从后台「上传论坛 v2」替换现有论坛
- 不能在不发新版 McWeb 的情况下卸载迁移、删掉 `Community::*` 代码

## 插件扩展（Extension）

插件用于 **扩展原版 McWeb**，而不是替代大应用。

| 扩展 | 运行位置 | 能做什么 | 不能做什么 |
|------|----------|----------|------------|
| **McWeb Connector** | MC 服务端 JVM | 拉任务、执行命令、上报在线/事件 | 直连数据库、改 Rails 路由 |
| **mcweb-node** | 宿主机 Go | 启停实例、备份、指标、Connector 代理 | 改论坛/商城逻辑 |
| **ZIP 前台模板** | Rails 静态资源 | 颜色 token、CSS、HTML 插槽 | 改 Vue 组件/路由 |
| **出站 Webhook** | Rails Job | 把订单/论坛事件推到外部系统 | 外部反向注入业务代码 |
| **Minecraft 集成规则** | 后台配置 | 条件触发预置动作 | 执行任意 Ruby |
| **商城子功能** | `StoreFeatures` | 开关物流/实体商品等 | 新增支付渠道 |

## 事件总线（插件钩子 / code event listeners）

McWeb 提供进程内**事件总线** `Mcweb::Events`（`lib/mcweb/events.rb`），对标 XenForo 的
「code event listeners」：扩展可以在**不修改核心代码**的前提下订阅核心动作。它是对 Rails 内建
`ActiveSupport::Notifications` 的轻量封装（不重复造轮子），事件统一发布在 `<event>.mcweb` 命名空间下。

### 订阅

在初始化器中订阅（例如 `config/initializers/`，或你自己的扩展加载入口）：

```ruby
Mcweb::Events.subscribe("forum.post.created") do |payload|
  post  = payload[:post]   # Community::Post
  topic = payload[:topic]  # Community::Topic
  # 你的扩展逻辑：推送到外部系统、打积分、写审计……
end
```

- 监听器**同步**执行，且在触发它的数据库事务**提交之后**（事件从提交后的 side-effect 路径发出），
  因此可安全读取已持久化记录。
- 监听器抛出的异常会被**捕获并记录**，绝不会中断核心请求流程（与站内通知广播的 rescue 策略一致）。
- `Mcweb::Events.subscribe` 返回一个句柄，可用 `Mcweb::Events.unsubscribe(handle)` 退订。

### 发布

核心代码在自然的 side-effect 位置发布事件；你也可以发布自定义事件：

```ruby
Mcweb::Events.publish("forum.post.created", post: post, topic: topic)
```

### 核心事件目录（稳定 API）

见 `Mcweb::Events::CATALOG`：

| 事件 | 负载键 | 触发点 |
|------|--------|--------|
| `forum.topic.created` | `topic`, `post` | 新主题发布 |
| `forum.post.created` | `topic`, `post` | 新回帖发布 |
| `forum.post.edited` / `.deleted` / `.restored` / `.rejected` / `.approved` | `topic`, `post` | 帖子生命周期 |
| `forum.topic.solved` / `.moved` | `topic`, `post` | 主题状态变更 |
| `forum.reaction.added` / `.removed` | `post`, `user`, `emoji`, `counts` | 反应增减 |
| `identity.user.registered` | `user`, `ip_address` | 新用户注册完成 |

> 论坛事件的中央发出点是 `Community::DispatchForumEventWebhook`：无论是否配置了出站 Webhook，
> 内部事件总线都会收到事件（出站 Webhook 仍受其 URL/开关门控）。

### 事件 Webhook 订阅（事件总线的出站投递）

除了进程内监听器，事件总线还可将任意 catalog 事件（或 `*` 全部）投递到外部 URL：
后台 **系统 → 事件 Webhook 订阅**（`Administration::WebhookSubscription`）配置 `event` + `url` + 可选签名密钥，
每次匹配事件触发时经 `Administration::WebhookFanout` 异步投递（HMAC-SHA256 签名、失败自动重试计数、连续失败自动停用）。
无订阅时零开销，因此这是给插件/外部系统「订阅核心事件」的即用集成点。

## 能否「随意扩展」？

**结论：不能随意扩展 Rails 业务逻辑；只能在文档列出的边界内扩展。**

| 需求 | 现状 | 推荐路径 |
|------|------|----------|
| 关掉论坛只留商城 | ✅ | 后台功能开关 / `FeatureFlags` |
| 换皮肤/页眉页脚 | ✅ | ZIP 模板 |
| 游戏内发货/绑定 | ✅ | Connector + 协议 |
| 宿主机管服 | ✅ | mcweb-node |
| 把订单推到 ERP | ✅ | 商城 Webhook |
| 在核心动作上挂钩自定义逻辑 | ✅ | 事件总线 `Mcweb::Events`（code event listeners） |
| 新增一种帖子类型/商品类型 | ❌ 需改代码 | Fork McWeb 或提 PR |
| 第三方 Ruby gem 插件市场 | ❌ 未实现 | 未来可做 Rails Engine，当前无 |
| 运行时加载 `.rb` 插件 | ❌ 无沙箱 | 安全风险，未做 |

## 与现有机制对照

| 机制 | 层级 | 说明 |
|------|------|------|
| `FeatureFlags` | 大应用开关 | 控制论坛/商城/Minecraft/博客入口 |
| `Commerce::StoreFeatures` | 大应用内子开关 | 仅商城内部能力 |
| `Identity::AccountAccess::ADMIN_MODULES` | 大应用后台授权 | staff 按 forum/store/minecraft/system/website 授权 |
| `SiteSetting` | 全局配置 | 键值配置，非代码插件 |
| `Frontend::Template` | 插件扩展 | 纯展示层 |
| `plugins/mcweb-connector` | 插件扩展 | 游戏服端，非 Web 端 |

## 后台查看目录

管理员可在 **系统 → 应用与扩展**（`/admin/system/applications`）查看当前注册的三层清单及启用状态。

## 未来方向（未实现）

若要做真正的「可安装大应用」：

1. 将 `Community` / `Commerce` 拆为 **Rails Engine**（`mcweb-forum`、`mcweb-store` gem）
2. 发行版 `Gemfile` 声明依赖，迁移由 Engine 自带
3. 插件市场仅限 **Extension** 层：Connector 协议扩展、Webhook 订阅、模板 ZIP

当前仓库仍为 **单仓库 monolith**，上述拆分尚未开始。
