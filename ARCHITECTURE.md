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
| 已读追踪 / 未读徽章 | `Community::ReadState` + 分区列表展示 |
| 站内通知 | `Community::NotifyTopicReply` + `/forum/notifications` |
| 举报闭环 | 主题/帖子举报 + 管理后台审核 |
| 移动 / 隐藏 | `MoveTopic`、`ModeratePost` |
| 版主操作 | `ModerateTopic`（锁定/置顶/隐藏） |
| 分页 | Pagy 应用于主题帖列表 |
| 反垃圾 | 速率限制、禁言、重复检测 |
| @提及 | `Community::ProcessMentions` + 通知 |
| Markdown 渲染 | `Community::FormatPostBody`（粗体/斜体/代码/链接） |
| 书签 | `Community::ToggleBookmark` |
| 标签 | `Community::SyncTopicTags`（最多 5 个）+ `/forum/tags/:slug` |
| 用户资料 | `/forum/users/:username` |
| 关注列表 | `/forum/watching` |
| 书签列表 | `/forum/bookmarks` |
| 最新动态 | `/forum/latest` |
| 标签云 | `/forum/tags` |
| 私信 | `Community::CreateConversation` + `/forum/conversations` |
| 编辑主题/标签 | `Community::EditTopic` |
| 编辑历史 | `PostEdit` + `/forum/posts/:id/edits` |
| Gravatar 头像 | `HasAvatar` concern |
| 通知偏好 | `/forum/preferences` |
| 搜索增强 | 分区筛选 + 分页 |
| 未读主题列表 | `/forum/unread` |
| 分区关注 | `ToggleSectionSubscription` + 新主题通知 |
| 精选主题 | `ModerateTopic` feature/unfeature |
| 主题排序 | `?sort=` activity/newest/replies/views |
| 禁言管理 | `CreateMute` / `RemoveMute` + 管理后台 |
| 帖子预览 | `POST /forum/preview` |
| 用户活动流 | 资料页最近回复 |
| 订单邮件 | `Commerce::OrderMailer` |
| 销售统计 | 管理仪表盘营收/低库存 |
| 评价需购买 | `CreateReview` 校验已付款订单 |
| 商品变体管理 | 后台嵌套变体 CRUD |
| 用户拉黑 | `Community::ToggleUserBlock` + 过滤被拉黑用户主题 |
| 主题投票 | `Community::Poll` + `VotePoll`（2–10 选项） |
| 主题草稿 | `SaveTopicDraft` / `PublishTopicDraft` + `/forum/drafts` |
| RSS 订阅 | `/forum/latest.rss`、`/forum/sections/:slug.rss` |
| SEO 元数据 | 主题页 Inertia `<Head>` title/description |
| 发帖预览 | 新建主题页 Markdown 实时预览 |
| 发帖含投票 | 新建主题可选投票问题与选项 |
| 嵌套回复 | `parent_post_id` + 主题页缩进展示 |
| 富文本 Markdown | 标题/列表/代码块/图片/剧透 |
| 慢速模式 | `slow_mode_seconds` 主题级发帖冷却 |
| Wiki 主题 | 所有登录用户可协作编辑帖子 |
| 已解决标记 | `MarkTopicSolved` + 楼主/版主标答案 |
| 用户简介 | `users.bio` + 资料页编辑 |
| PostgreSQL 全文搜索 | `to_tsvector` + `plainto_tsquery` |
| 拉黑过滤完善 | 搜索/标签/书签/关注/未读/帖子列表 |
| 拉黑禁止私信 | `CreateConversation` / `SendMessage` 校验 |
| 信任等级 | `Community::TrustLevel`（0–4）新成员禁止发链接 |
| 帖子级书签 | `Community::TogglePostBookmark` + `forum_post_id` |
| 私信站内通知 | `Community::NotifyPrivateMessage` + 偏好 `forum.private_message` |
| 标签 RSS | `/forum/tags/:slug.rss` |
| 论坛 Sitemap | `/forum/sitemap.xml`（最近 500 主题） |
| 分区后台 Inertia | `Admin::Forum::SectionsController` + 发帖/回复角色权限 |
| 主题 OG 元数据 | `Topics/Show.vue` Open Graph title/description |
| 用户信任等级展示 | 资料页 `trust_level` / `trust_name` |

## 商城功能

| 功能 | 实现 |
|------|------|
| 商品变体 | `ProductVariant` + 商品详情页选择 |
| 分类筛选 | 商品列表 `?category=` |
| 库存 / 限购校验 | `Commerce::ValidateCartItem` |
| 优惠券 | `Commerce::PreviewCoupon` + `ApplyCoupon` |
| 游客购物车合并 | `Commerce::MergeGuestCart`（登录时） |
| 支付后自动发货 | `ConfirmPayment` → `FulfillOrderJob` |
| 假支付测试页 | `Payments::FakeController` `/payments/fake/:id` |
| 订单取消 | `Commerce::CancelOrder`（待支付状态，恢复库存） |
| 发货状态展示 | 订单详情页显示 fulfillment 状态 |
| 商品搜索/排序 | `?q=`、`price_asc` / `price_desc` |
| 管理后台退款 | `Commerce::ProcessRefund` 全额/部分退款（恢复库存） |
| 客户退款申请 | `Commerce::RequestRefund` + 订单页申请 UI |
| 后台商品 CRUD | `Admin::Store::ProductsController` + Inertia 表单 |
| 后台分类 CRUD | `Admin::Store::CategoriesController` |
| 后台优惠券 CRUD | `Admin::Store::CouponsController` |
| 商品图片 | `store_products.image_url` + 列表/详情展示 |
| 心愿单 | `Commerce::ToggleWishlist` + `/store/wishlist` |
| 商品评价 | `Commerce::CreateReview` + 星级展示 |
| 评价后台审核 | `Admin::Store::ReviewsController` 显示/隐藏 |
| 退款邮件 | `OrderMailer#refund_processed` |
| 退款审批修复 | `ProcessRefund` 复用 pending 客户申请，避免重复记录 |
| 商品图库 | `store_products.gallery_urls`（jsonb）+ 详情页轮播展示 |
