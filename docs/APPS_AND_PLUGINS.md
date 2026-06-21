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

## 能否「随意扩展」？

**结论：不能随意扩展 Rails 业务逻辑；只能在文档列出的边界内扩展。**

| 需求 | 现状 | 推荐路径 |
|------|------|----------|
| 关掉论坛只留商城 | ✅ | 后台功能开关 / `FeatureFlags` |
| 换皮肤/页眉页脚 | ✅ | ZIP 模板 |
| 游戏内发货/绑定 | ✅ | Connector + 协议 |
| 宿主机管服 | ✅ | mcweb-node |
| 把订单推到 ERP | ✅ | 商城 Webhook |
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
