# 架构说明

## 模块边界

```
app/
  models/          # 按领域命名空间：Website、Community、Commerce、Minecraft、Payments
  services/        # 业务命令对象，Controller 保持精简
  jobs/            # Active Job + Solid Queue
  components/ui/   # 通用设计系统（直角、无卡片）
  controllers/     # 按模块分命名空间
```

## 数据流

### 支付流程

1. 用户下单 → `Commerce::CreateOrder`
2. 创建 `Payments::Record` → Provider 发起支付
3. Webhook → `Payments::WebhookProcessor`（签名验证 + 事件幂等）
4. `Commerce::ConfirmPayment`（行锁 + 状态检查）
5. `Commerce::FulfillOrderJob` → 创建 `Commerce::Fulfillment`

### 发货流程

1. `Commerce::CreateFulfillment` 生成唯一 `delivery_id`
2. `Minecraft::DispatchFulfillmentJob` 创建 Connector 任务
3. 插件拉取任务 → 本地检查 `delivery_id` → 执行命令
4. 回调确认 → 更新 Fulfillment 状态

两边均保证幂等：数据库唯一约束 + 状态机检查。

## 缓存

- 公共官网区块、商品列表使用 Solid Cache
- 用户权限、购物车不共享缓存

## 后台任务队列

`critical` / `payments` / `minecraft` / `mailers` / `notifications` / `media` / `maintenance`

## 前端架构（官网 vs 业务 Portal vs 管理后台）

同一 Rails 应用内采用 **三套 Vue 布局**，通过 Inertia.js + Vue 3 渲染：

| 区域 | 布局 | 风格 |
|------|------|------|
| 官网首页 / 博客 | `WebsiteLayout.vue` | 营销风渐变与动效 |
| 论坛 / 商城 / 账户 | `PortalLayout.vue` | shadcn-vue 功能界面 |
| 管理后台 | `AdminLayout.vue` | shadcn-vue 侧边栏运维界面 |
| 安装向导 | ERB（`setup`） | 一次性初始化 |

安装向导与 API（Webhook、Minecraft Connector）保留服务端接口，不迁移 Vue。

技术栈指纹：`inertia.ts` 设置 `window._rails_loaded`，布局保留 `meta generator` / `X-Powered-By` 响应头供 Wappalyzer 识别 Ruby on Rails。

## 论坛功能（对标 Discourse / XenForo）

| 功能 | 实现 |
|------|------|
| 发帖含首帖 | `Community::CreateTopic` 创建 floor 1  opening post |
| 回复 / 引用 | `Community::CreatePost` + `quoted_post` |
| 编辑（15 分钟窗口） | `Community::EditPost` |
| 软删除 | `PostsController#destroy` |
| 表情反应 | `Community::ToggleReaction`（👍❤️😂🎉👀） |
| 关注主题 | `Community::ToggleSubscription` |
| 已读追踪 | `Community::ReadState` |
| 版主操作 | `Community::ModerateTopic`（锁定/置顶） |
| 分页 | Pagy 应用于主题帖列表 |
| 反垃圾 | 速率限制、禁言、重复检测 |

## 商城功能

| 功能 | 实现 |
|------|------|
| 商品变体 | `ProductVariant` + 商品详情页选择 |
| 分类筛选 | 商品列表 `?category=` |
| 库存 / 限购校验 | `Commerce::ValidateCartItem` |
| 优惠券 | `Commerce::PreviewCoupon` + `ApplyCoupon` |
| 游客购物车合并 | `Commerce::MergeGuestCart`（登录时） |
| 支付后自动发货 | `ConfirmPayment` → `FulfillOrderJob` |
