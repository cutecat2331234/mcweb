# 大应用与插件扩展

McWeb 是 **Rails 模块化单体**，同时提供面向部署流程的可信 Ruby Plugin SDK。它不是
WordPress/Discourse 式由管理员在浏览器上传 ZIP 的插件市场：Ruby 插件必须随部署安装并重启或重载进程，
而且会以 McWeb 进程的完整权限运行。本文说明三层边界、可信边界和运行状态目录。

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
    可信 Ruby 插件（Rails 进程内、完全信任）· Connector (JVM)
    · mcweb-node (Go) · ZIP 模板 · Webhook · 集成规则
```

代码注册表：`Mcweb::ApplicationRegistry`（`lib/mcweb/application_registry.rb`）。
其中 `freely_extensible? == true` 仅表示支持**完全可信**的 Ruby 扩展；插件既可来自部署目录，
也可由有权限的管理员上传已审查本地 ZIP。它不表示能够隔离或安全执行不可信代码。
`plugin_installation_mode == :deployment_or_reviewed_local_package` 明确了这一运维边界。

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
- 独立 RBAC 权限键与 `admin_module_grants`（站点团队按模块授权）
- 可通过 `FeatureFlags` **整体关闭前台入口**（论坛与商城至少保留一个）

### 大应用不是

- 不能从后台「上传论坛 v2」替换现有论坛
- 不能在不发新版 McWeb 的情况下卸载迁移、删掉 `Community::*` 代码

## 插件扩展（Extension）

插件用于 **扩展原版 McWeb**，而不是替代大应用。扩展分为两类：

- 部署时安装的 Ruby 插件运行在 Rails 进程内，拥有与 McWeb 相同的代码、数据库、服务和环境权限。
- Connector、Node、模板和 Webhook 等外部或声明式扩展仍受各自协议和数据面约束。

| 扩展 | 运行位置 | 能做什么 | 不能做什么 |
|------|----------|----------|------------|
| **可信 Ruby 插件 SDK** | Rails 进程 | 注册事件监听器、调用宿主 API；支持部署目录和后台已审查本地包 | 不能作为不可信代码运行；不远程下载、无沙箱、无发布者签名或自动升级 |
| **McWeb Connector** | MC 服务端 JVM | 拉任务、执行命令、上报在线/事件 | 直连数据库、改 Rails 路由 |
| **mcweb-node** | 宿主机 Go | 启停实例、备份、指标、Connector 代理 | 改论坛/商城逻辑 |
| **ZIP 前台模板** | Rails 静态资源 | 颜色 token、CSS、HTML 插槽 | 改 Vue 组件/路由 |
| **出站 Webhook** | Rails Job | 把订单/论坛事件推到外部系统 | 外部反向注入业务代码 |
| **Minecraft 集成规则** | 后台配置 | 条件触发预置动作 | 执行任意 Ruby |
| **商城子功能** | `StoreFeatures` | 开关物流/实体商品等 | 新增支付渠道 |

## 可信 Ruby 插件 SDK

部署插件放在 `plugins/**/mcweb_plugin.yml`；受管插件也会在后台上传后进入同一受控插件根目录，
由 `Mcweb::Plugins` 发现并加载 Ruby 入口。manifest 提供严格的 `vendor/name` ID、SemVer
版本、SDK API 版本、依赖和能力声明；依赖按拓扑顺序激活。完整格式和开发示例见
[`PLUGIN_SDK.md`](./PLUGIN_SDK.md)。

> Ruby 插件是**完全可信代码**。`capabilities` 只用于兼容性检查和审计说明，不是权限控制，
> 也不会形成安全沙箱。只应通过正常部署流程安装经过审查的源码。

后台插件包管理提供本地 ZIP 上传、严格预期 SHA-256、安装/升级、启用/停用、可恢复文件隔离卸载，
以及受信 `setup` 的安装、升级和 teardown 步骤。包文件、收据、当前进程 runtime 与同一事务连接
上的数据库步骤在失败时回滚；成功 teardown 仍可能永久删除插件自有数据，“文件可恢复”不等于
“数据可恢复”。操作前必须审查 setup 代码并备份。

该入口不提供远程目录、远程下载、发布者签名、自动升级或不可信代码隔离。当前 runtime reload
只作用于执行操作的 Rails 进程，多进程 generation/ack 尚未完成；生产变更仍需协调重启或重载
全部 Rails/Worker 进程。紧急情况下可设置 `MCWEB_DISABLE_PLUGINS=1`。

运行时提供只读快照：

```ruby
Mcweb::Plugins.list
Mcweb::Plugins.diagnostics
```

后台“应用与扩展”还维护一份数据库持久清单。成功的非 dry-run
安装、升级、启用、禁用、回滚、恢复和卸载会同步：

- `PluginRelease`：版本状态（`active` / `disabled` / `rollback` /
  `uninstalled`）、安全的 manifest 描述符、manifest/package SHA-256；
- `PluginContribution`：规范化贡献描述符、descriptor SHA-256 与可选的
  schema SHA-256；
- `PluginFile`：仅限插件内相对路径、预期/实际大小与 SHA-256、健康状态。

拥有 `system.plugins.diagnostics` 的管理员可以执行“对账并补录”。该操作
不会修改插件文件、receipt 或运行时，只会幂等更新数据库清单并写审计日志；
因此也可补录数据库迁移之前已经存在的插件。receipt、运行时与文件系统不一致
时会保留明确的诊断代码，不会悄悄把其中任意一方当成正确结果。后台响应和审计
元数据不包含绝对路径、source URL、异常原文、凭据或插件设置值。

后台 **系统 → 应用与扩展** 会展示当前进程已加载插件的版本、依赖、能力声明、状态、监听器数量、
最近错误，以及加载/激活/派发诊断。

插件还可通过 `contributions.settings` 声明严格、版本化的设置 schema。设置按插件与 schema
版本隔离、整包加密并采用追加式修订；显式迁移不会覆盖旧版本，回滚也只追加新修订。后台
**系统 → 插件设置** 由 Arco Design 根据 schema 生成表单，且敏感值只显示“已配置”状态，
不会回显明文。运行时通过 `plugin.api.settings` 读取或修改自己的命名空间，不能借此修改宿主
`SiteSetting`。

插件可通过 `contributions.jobs` 声明自己的后台任务键、重试/租约策略和封闭参数 schema，
再用 `plugin.job("key")` 注册处理器。运行时只能通过 `plugin.api.jobs` 入队、查询、取消或恢复
本插件任务，队列里只有不透明的任务 public ID，不接受 Ruby 类名或跨插件任务键。参数整包
加密且不会进入 DTO、队列或错误日志。投递语义是 at-least-once；处理器应使用
`context.run_public_id` 对外部副作用做幂等。插件停用、缺失或版本/声明不兼容时任务暂停而不
消耗处理尝试；不兼容升级应取消旧任务并按新声明重新入队。

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
| `commerce.order.paid` | `order` | 可履约订单完成付款 |
| `commerce.payment.confirmed` / `.failed` / `.refunded` | `payment`, `order`；退款时另含 `refund` | 支付成功、终态失败、每笔退款完成 |
| `commerce.refund.requested` / `.processed` / `.rejected` | `refund`, `payment`, `order` | 退款申请生命周期 |
| `commerce.inventory.reserved` / `.released` / `.confirmed` / `.adjusted` | `inventory`, `movement`，有订单时另含 `order` | 每笔实际库存流水提交 |
| `commerce.fulfillment.dispatched` / `.retryable_failed` / `.failed` / `.completed` / `.cancelled` | `fulfillment`, `order`，按事件可含 `attempt`, `result` | 每次权威履约状态转换 |
| `identity.user.registered` | `user`, `ip_address` | 新用户注册完成 |
| `plugin.settings.changed` | `plugin_id`, `schema_version`, `schema_digest`, `revision`, `change_kind`, `changed_keys` | 插件设置修订提交后；不包含设置值 |

商业事件统一通过 `ActiveRecord.after_all_transactions_commit` 和
`Mcweb::Events.defer_until_success` 发布：事务回滚不会产生事件，幂等重放不会重复发布。
插件执行外部副作用时仍应使用订单 public ID、退款 ID、库存 movement public ID，或
`delivery_id + attempt.number` 做幂等。负载是固定白名单快照，只包含状态、金额、币种、
数量、公开/稳定标识和受限错误码；不会包含用户名、邮箱、地址、备注/原因、支付渠道
引用、provider secret/metadata、原始 Webhook 或 Connector 响应。履约插件应监听
`commerce.order.paid`，不要把 `commerce.payment.confirmed` 当作自动发货信号。

> 论坛事件的中央发出点是 `Community::DispatchForumEventWebhook`：无论是否配置了出站 Webhook，
> 内部事件总线都会收到事件（出站 Webhook 仍受其 URL/开关门控）。

### 事件 Webhook 订阅（事件总线的出站投递）

除了进程内监听器，事件总线还可将任意 catalog 事件（或 `*` 全部）投递到外部 URL：
后台 **系统 → 事件 Webhook 订阅**（`Administration::WebhookSubscription`）配置 `event` + `url` + 可选签名密钥，
每次匹配事件触发时经 `Administration::WebhookFanout` 异步投递（HMAC-SHA256 签名、失败自动重试计数、连续失败自动停用）。
无订阅时零开销，因此这是给插件/外部系统「订阅核心事件」的即用集成点。
商业事件的出站数据仍会再次经过逐字段白名单清洗；即使队列参数被手工构造，未声明字段
也会在真正发送前删除。

## 如何扩展 Rails 业务逻辑？

**结论：可以通过部署安装的可信 Ruby 插件扩展，但这等同于部署应用代码，不是隔离的低权限插件。**

| 需求 | 现状 | 推荐路径 |
|------|------|----------|
| 关掉论坛只留商城 | ✅ | 后台功能开关 / `FeatureFlags` |
| 换皮肤/页眉页脚 | ✅ | ZIP 模板 |
| 游戏内发货/绑定 | ✅ | Connector + 协议 |
| 宿主机管服 | ✅ | mcweb-node |
| 把订单推到 ERP | ✅ | 商城 Webhook |
| 在核心动作上挂钩自定义逻辑 | ✅ | 可信 Ruby Plugin SDK + 事件 DTO |
| 新增一种帖子类型/商品类型 | ❌ 需改代码 | Fork McWeb 或提 PR |
| 后台上传已审查本地 Ruby ZIP | ✅ | 有权限管理员 + 严格预期 SHA-256；完整信任模型不变 |
| 远程第三方目录、下载或自动升级 | ❌ 未实现 | 由可信发布流程先下载、审查并计算摘要 |
| 加载 `.rb` 插件 | ✅ 完全信任 | `plugins/**/mcweb_plugin.yml`；无沙箱，与 Rails 进程同权 |

## 与现有机制对照

| 机制 | 层级 | 说明 |
|------|------|------|
| `FeatureFlags` | 大应用开关 | 控制论坛/商城/Minecraft/博客入口 |
| `Commerce::StoreFeatures` | 大应用内子开关 | 仅商城内部能力 |
| `Identity::AccountAccess::ADMIN_MODULES` | 大应用后台授权 | staff 按 forum/store/minecraft/system/website 授权 |
| `SiteSetting` | 全局配置 | 键值配置，非代码插件 |
| `Frontend::Template` | 插件扩展 | 纯展示层 |
| `Mcweb::Plugins` | 可信 Ruby 插件 | 部署/受管本地包、依赖激活、生命周期、事件、版本化设置、任务和运行诊断 |
| `plugins/mcweb-connector` | 插件扩展 | 游戏服端，非 Web 端 |

## 后台查看目录

管理员可在 **系统 → 应用与扩展**（`/admin/system/applications`）查看三层清单、大应用启用状态、
当前 Rails 进程的 Ruby 插件状态、包操作记录和诊断。具备 `system.plugins.manage` 权限的管理员
还可上传已审查本地 ZIP，并执行安装/升级、启停和带精确插件 ID 确认的 teardown 卸载。
卸载请求同时绑定页面所见版本与安装收据 SHA-256，生命周期管理器会在独占文件锁内、
执行 teardown 前重新核对，旧页面不能卸载随后升级的新版本。

## 未来方向（未实现）

可信 Ruby Plugin SDK 已支持部署式和受管本地包扩展，但以下能力仍未提供：

1. 将 `Community` / `Commerce` 拆为可独立安装的大应用 Rails Engine
2. 远程插件目录、远程下载和自动升级（发布者签名与不可信代码沙箱不在当前路线范围）
3. 跨进程 generation/ack、安装后文件健康检查，以及明确区分“保留数据/清除数据”的卸载模式

当前仓库仍为 **单仓库 monolith**；部署 Ruby 插件不能卸载或替换内建大应用。
