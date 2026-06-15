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
| 论坛邮件通知 | `Community::ForumMailer` + 偏好邮件渠道 |
| 访问主题自动已读通知 | 打开主题页标记相关 `forum.topic_reply` 通知 |
| 全部标为已读 | `MarkAllTopicsRead` + `/forum/unread/mark_all_read` |
| 帖子书签列表 | 书签页分开展示主题/帖子书签 |
| 游客可见反应数 | 未登录用户可查看表情统计 |
| 子分区展示 | 板块列表嵌套显示 `children` + 主题数 |
| 投票自动关闭 | `poll_closes_days` 创建时设置 `closes_at` |
| 私信 Markdown | 私信对话页渲染 `body_html` |
| 移动权限独立 | `can_move` 与 `forum.topics.move` 权限 |
| 慢速模式路由修复 | `PATCH slow_mode` → `update_slow_mode` |
| 主题列表已解决徽章 | `TopicTitleBadges` + `serialize_topic.solved` |
| 主题筛选 | 未解决/已解决/我的/我参与的（`TopicFilterable`） |
| 搜索增强筛选 | 作者、标签、解决状态 |
| 取消已解决 | `UnsolveTopic` + `POST unsolve` |
| 通知点击查看已读 | `notifications#visit` 自动标记并跳转 |
| 访问主题标记多类型通知已读 | 回复/提及/分区新主题 |
| 论坛分类后台 CRUD | `Admin::Forum::CategoriesController` |
| 子板块父级设置 | 分区后台 `parent_id` 选择器 |
| 举报详情链接 | 管理后台跳转主题/帖子 |
| 提及/分区邮件通知 | `ForumMailer#mention` / `#section_topic` |
| 导航修复 | 「偏好」与通知铃铛分离 |

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
| 待支付订单过期 | `ExpirePendingOrdersJob`（30 分钟自动取消释放库存） |
| 取消恢复优惠券 | `CancelOrder` 回滚 `coupon.used_count` |
| 订单履约完成 | `SyncOrderFulfillmentStatus` + `order_fulfilled` 邮件 |
| 发货重试修复 | `RetryFulfillment` 重新排队 `DispatchFulfillmentJob` |
| 变体库存判断 | `Product#in_stock?` 有变体时检查变体库存 |
| 购买数量选择 | 商品详情页数量输入 |
| 发货配置后台 | `fulfillment_config` JSON 编辑 |
| 连接器失败处理 | `TaskDispatcher` 根据结果标记 failed |
| 优惠券计算统一 | `ApplyCoupon` 使用 `Coupon#calculate_discount` |
| 变体必选校验 | 有变体商品必须选择规格 |
| 发货重试去重 | `DispatchFulfillmentJob` 跳过已有 pending 任务 |
| 全额退款恢复优惠券 | `ProcessRefund#restore_coupon_usage!` |
| 订单状态中文标签 | `ORDER_STATUS_LABELS` + `status_label` |
| 订单支付渠道选择 | 订单详情页选择 Provider |
| 购物车导航徽章 | `PortalLayout` 显示购物车数量 |
| 发货重试按钮条件显示 | 仅 pending/failed 显示 |

### 第十一轮（安全 / 论坛 / 商城）

| 功能 | 实现 |
|------|------|
| 草稿/隐藏主题访问控制 | `Community::TopicVisibility` + `ensure_topic_visible!` |
| 发布草稿完整校验 | `PublishTopicDraft` 分区权限、禁言、链接限制 |
| 分区发帖权限 UI | `canCreateTopic` 与后端 `section.allowed?` 一致 |
| 回复权限 UI | `canReply` 含锁定与分区回复权限 |
| 未读列表 SQL 优化 | `ReadState.with_unread_for` scope |
| 未读不计隐藏帖 | `unread_count` 仅统计 `published` 帖子 |
| 删帖同步 last_post | `SyncTopicLastPost` + `posts#destroy` |
| 主题前缀 | 分区 `prefixes` jsonb + 发帖选择 + `TopicTitleBadges` |
| 搜索 GIN 索引 | `forum_topics` / `forum_posts` tsvector GIN |
| 用户获赞数 | 资料页 `likes_received` |
| 商城邮件偏好 | `/store/preferences` + `OrderMailer` 按偏好发送 |
| 订单列表分页 | `OrdersController#index` + Pagy |
| 购物车累加库存校验 | `ValidateCartItem` `cart:` / `replace_quantity:` |
| 游客购物车合并校验 | `MergeGuestCart` 失败保留 guest cart |
| 支付重试去重 | `CheckoutController` 复用 pending payment |
| 取消订单作废支付 | `CancelOrder#cancel_pending_payments!` |
| 低库存含变体 | `SalesMetrics#low_stock_variant_count` |

### 第十二轮（论坛 / 商城深化）

| 功能 | 实现 |
|------|------|
| 回复/编辑 Markdown 预览 | `Topics/Show.vue` 复用 `/forum/preview` |
| 编辑历史 diff | `DiffLines` + `Posts/Edits.vue` 高亮 |
| 链接 Onebox | `FetchLinkPreview` + `FormatPostBody` |
| 敏感词过滤 | `CensoredWord` + `FilterCensoredWords` + 后台管理 |
| 主题合并 | `MergeTopics` + 版主 UI |
| 用户封禁后台 | `BanUser` / `UnbanUser` + Admin 用户页 |
| 论坛头衔/显示名 | `users.forum_title` + 资料页编辑 |
| 获赞帖子列表 | 用户资料页 `liked_posts` |
| 结账订单备注 | Checkout → `CreateOrder#notes` |
| 退款状态中文 | `REFUND_STATUS_LABELS` |
| 订单时间线 | `OrderEvent` 序列化 + 详情页 |
| 订单收据下载 | `orders#receipt` HTML |
| 相关商品 | 同分类推荐 |
| 游客购物车徽章 | `inertia_share` 会话购物车 |
| 弃购提醒邮件 | `AbandonedCartReminderJob` + `CartMailer` |
| 后台订单 CSV 导出 | `admin/store/orders#export` |

### 第十三轮（论坛 / 商城联动）

| 功能 | 实现 |
|------|------|
| @提及自动补全 | `MentionsController#search` + `MentionAutocomplete.vue` |
| 论坛动态流 | `ActivityController#index` + `/forum/activity` |
| 关注用户 | `UserFollow` + `ToggleUserFollow` + 资料页 / 我的关注 |
| 关注用户新主题通知 | `NotifyFollowedUserTopic` + 偏好 `forum.followed_topic` |
| 论坛邮件摘要 | `SendForumDigest` + `ForumDigestJob` + 偏好频率 |
| 通知分组展示 | `NotificationsController#group_notifications` |
| 草稿预览摘要 | `DraftsController` `body_excerpt` / `preview_html` |
| 注册/登录合并购物车 | `GuestCartMergeable` concern |
| 购物车优惠券预览 | `CartsController#preview_coupon` |
| 订单搜索/筛选 | `OrdersController#index` `q` / `status` |
| 低库存标识 | `Product#low_stock?` / `ProductVariant#low_stock?` |
| 到货通知 | `StockAlert` + `SubscribeStockAlert` + 补货 Job |

### 第十四轮（论坛 / 商城进阶）

| 功能 | 实现 |
|------|------|
| 帖子图片上传 | ActiveStorage + `UploadsController` + `ImageUploadButton` |
| 用户成就徽章 | `Badge` / `UserBadge` + `AwardBadge` / `CheckAutoBadges` |
| IP 封禁 | `IpBan` + `CheckIpBan` + 发帖校验 + 后台管理 |
| 主题定时发布 | `ScheduleTopic` + `PublishScheduledTopicsJob` |
| 商品问答 Q&A | `ProductQuestion` / `ProductAnswer` + 商品详情页 |
| 心愿单分享 | `wishlist_share_token` + 公开分享页 |
| Stripe 支付骨架 | `StripeProvider`（无密钥时测试模式） |
| PDF 订单收据 | `GenerateOrderReceiptPdf`（Prawn） |

### 第十五轮（论坛 / 商城编辑器与运营）

| 功能 | 实现 |
|------|------|
| Markdown 工具栏编辑器 | `MarkdownEditor.vue`（粗体/斜体/代码/链接/图片/预览） |
| 发帖/回复编辑器升级 | `Topics/New.vue` / `Topics/Show.vue` 接入 `MarkdownEditor` |
| 群组私信 | `CreateGroupConversation` + `Conversation#is_group` / `title` / `creator` |
| 1:1 私信与群组隔离 | `CreateConversation#find_existing` 排除 `is_group` |
| 群组发信拉黑校验 | `SendMessage` 检查所有对方用户 |
| 群组通知标题 | `NotifyPrivateMessage` 群组标题格式 |
| 标签描述与权限 | `Tag#staff_only` + `SyncTopicTags` 权限校验 |
| 标签/徽章后台 CRUD | `Admin::Forum::TagsController` / `BadgesController` + Form 页 |
| 商品封面 ActiveStorage | `Product#cover_image` + `AttachProductCover` |
| 商品封面上传 API | `Admin::Store::UploadsController` |
| 商品问答后台隐藏 | `HideProductQuestion` + `ProductQuestionsController#hide` |
| Stripe Webhook 增强 | `Stripe-Signature` 头 + `checkout.session.completed` 元数据查找 |

### 第十六轮（论坛 / 商城体验与 Bug 修复）

| 功能 | 实现 |
|------|------|
| SyncTopicTags 失败回滚 | 发帖/定时/草稿路径标签校验失败时中止 |
| staff_only 标签隐藏 | `Tag.usable_by` 用于标签云与搜索 |
| 私信最新消息分页 | 默认显示最后一页 + Pagination |
| 私信已读回执 | 发送方可见对方已读用户名 |
| 标签关注 | `ToggleTagSubscription` + `NotifyTagTopic` |
| 主题筛选扩展 | 未读 / 零回复（`TopicFilterable`） |
| 反应通知 | `NotifyPostReaction` + 偏好设置 |
| 信任等级私信门槛 | `TrustLevel.can_send_pm?` |
| 精选商品 | `featured` + 首页区块 |
| 商品浏览量/排序 | `view_count` + popular/rating 排序 |
| 再次购买 | `ReorderFromOrder` |
| 心愿单批量加购 | `AddWishlistToCart` |
| 问答回复邮件 | `NotifyProductQuestionAnswered` |
| 问答恢复显示 | `ShowProductQuestion` + 后台 unhide |
| 商品版本/更新日志 | `version` + `changelog` |
| Bug 修复 | Stripe 签名验证、封面 image_url 同步、上传 attach 结果 |

### 第十七轮（论坛 / 商城精细化与 Bug 修复）

| 功能 | 实现 |
|------|------|
| LCS 行级 diff | `DiffLines` 使用 `diff/lcs` |
| 编辑帖子 @提及 | `ProcessNewMentions` + `EditPost` |
| 编辑说明 | `forum_post_edits.reason` |
| 草稿/定时发布通知补全 | `NotifyTagTopic` / `NotifyFollowedUserTopic` |
| 关注标签列表页 | `WatchedController#tags` |
| 热门主题排序 | `Topic.sorted("hot")` |
| 标签页排序 UI | `Tags/Show.vue` |
| 通知分组修复 | 私信按 `conversation_id` 分组 + 展开子项 |
| 反应总数显示 | `reactions_total` |
| 发帖权限守卫 | `TopicsController#new` |
| 评价有帮助投票 | `ReviewHelpfulVote` + `ToggleReviewHelpful` |
| 购买后可评价校验修复 | `CreateReview.purchased?` 扩展状态 |
| 仅买家可见评价表单 | `canReview` |
| 退款申请时间线 | `refund_requested` OrderEvent |
| 购物车优惠券传递 | session `pending_coupon_code` → 结账 |
| 订单优惠明细 | `discount_label` / `coupon_code` |
| 规格级到货通知 | `stockAlertVariantIds` |
| Bug 修复 | 私信分页 `pages`、限购排除未支付订单 |

### 第十八轮（论坛 / 商城体验深化与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 合并主题修复 | `TopicsController#set_topic` 包含 `merge` |
| 分页已读追踪 | 仅标记当前页最高楼层为已读 |
| 帖子书签索引修复 | 主题书签 partial unique index |
| 关注用户主题流 | `FollowsController#index` + `Following/Index.vue` |
| 回复草稿自动保存 | `Topics/Show.vue` localStorage |
| 主题自动关闭 | `auto_close_at` + `CloseScheduledTopicsJob` |
| 徽章获得通知 | `NotifyBadgeEarned` |
| 信任等级提升通知 | `NotifyTrustLevelUp` |
| 引用通知 | `NotifyPostQuoted` |
| 已解决通知 | `NotifyTopicSolved` |
| 反应用户列表 | `reaction_users` + title 提示 |
| 导航未读角标 | `forum_unread` inertia share |
| 上次阅读分隔线 | `lastReadFloor` |
| 编辑审查词过滤 | `EditPost` censored words |
| Wiki 公开编辑历史 | `can_view_edits?` wiki 主题 |
| 投票隐藏结果 | `hide_results_until_vote` |
| 搜索排序 | 主题/帖子 最新/最早 |
| @提及排除拉黑用户 | `MentionsController` |
| 心愿单规格加购修复 | `AddWishlistToCart` 选首个有货规格 |
| 已完成订单可退款 | `RequestRefund` + `refundable_order?` |
| 退款时间线补全 | `refund_processed` / `refund_rejected` |
| 取消订单事件去重 | 移除 `CancelOrder` 重复事件 |
| 仅看有货筛选 | `Product.with_stock` |
| 评价最有帮助排序 | `review_sort=helpful` |
| 到货通知管理 | `StockAlertsController#index/destroy` |
| 游客优惠券 session | 购物车预览保存 coupon |
| 已购评价徽章 | `verified_purchaser` |
| 已评价隐藏表单 | `userReview` + `canReview` |
| 发货状态中文 | `fulfillment_status_label` |
| 数字商品下载 | 订单 `downloads` 来自 fulfillment_snapshot |

### 第十九轮（论坛 / 商城导航与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 标为未读 | `MarkTopicUnread` + 主题页按钮 |
| 跳到未读 / 跨页锚点 | `post_id` / `unread=1` 分页解析 |
| 帖子锚点自动滚动 | `Topics/Show.vue` hash scroll |
| 复制永久链接 | 帖子「复制链接」 |
| 可点击引用块 | 引用跳转 `#post-{id}` |
| 搜索排序 UI | `Search/Index.vue` topic/post sort |
| 搜索帖子锚点 | `serialize_search_post` |
| 私信未读角标 | `messages_unread` inertia share |
| 关注动态拉黑过滤 | `FollowsController` + `BlockedUsersFilterable` |
| Markdown 删除线 | `~~text~~` in `FormatPostBody` |
| 已购徽章修复 | `serialize_review` 真实校验 |
| 评价去重/分页/星级筛选 | `ProductsController` |
| 不能给自己点有帮助 | `ToggleReviewHelpful` |
| 后台拒绝退款 | `RejectRefund` + admin action |
| 已完成订单后台退款 | admin `refundable_admin_status?` |
| 退款审核中提示 | `refund_pending` on order |
| 游客优惠券持久化 | cart show + clear coupon |
| 结账预览写 session | `checkout#preview_coupon` |
| 购物车商品链接 | `serialize_cart_item` |
| 心愿单库存/移除 | `Wishlist/Index.vue` |
| 商品列表评分 | `average_rating` on list |
| 到货通知增强 | 订阅时间、有货标识、规格校验 |
| 发货记录中文 | fulfillments `status_label` |

### 第二十轮（论坛 / 商城深度功能与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 书签备注/提醒 | `UpdateBookmark` + `forum_bookmarks.note/remind_at` |
| 多选投票 | `Poll#multiple_choice` + `VotePoll` 多票 |
| 手动关闭投票 | `ClosePoll` + `polls#close` |
| Markdown 增强 | 引用/有序列表/表格/视频嵌入/代码复制按钮 |
| 用户签名 | `users.forum_signature` + 帖子底部展示 |
| 最后在线 | `last_seen_at` + `TouchLastSeen` |
| 成员目录 | `MembersController` + `/forum/members` |
| 群组增删成员 | `AddConversationParticipant` / `RemoveConversationParticipant` |
| 编辑版本恢复 | `RestorePostEdit` + `posts#restore_edit` |
| 分区未读计数 | `ReadState.unread_count_for_section` |
| 主题内搜索 | `topics#show?q=` |
| 自定义头像 | `User#forum_avatar` ActiveStorage |
| 优惠券品类/商品限制 | `Coupon#product_ids/category_ids` |
| 心愿单记住规格 | `WishlistItem#variant_id` |
| 评价加载更多 | `Products/Show.vue` load more |
| 数字下载鉴权 | `GenerateDownloadToken` + `DownloadsController` |
| 首页精选商品 | `Website::Home` featured products |
| 退款拒绝邮件 | `OrderMailer#refund_rejected` |

### 第二十一轮（论坛 / 商城 Bug 修复与深度功能）

| 功能 | 实现 |
|------|------|
| 评价加载更多修复 | `ProductsController#show` 累积分页（`review_page * per_page`） |
| 书签提醒时间修复 | `Bookmarks/Index.vue` 使用 `remind_at_input`；controller 返回 ISO |
| 群组移除成员 URL | `conversations_controller` 每参与者 `remove_url` |
| 书签到期提醒 | `BookmarkReminderJob` + `NotifyBookmarkReminder` + 偏好 `forum.bookmark_reminder` |
| 置顶过期自动取消 | `pinned_until` + `UnpinExpiredTopicsJob` |
| 主题提升 / 限时置顶 | `ModerateTopic` 支持 `bump`、`pin_7` |
| Markdown 水平线 / 任务列表 | `FormatPostBody` 占位符方案 |
| 发帖多选投票 UI | `Topics/New.vue` |
| 群组 PM 群主转移 | 创建者离开时自动转移 |
| 群组 PM 离开 / 移除 | `RemoveConversationParticipant` 权限化 |
| 优惠券每人限用 | `Coupon#per_user_limit` |
| 优惠券首单专享 | `Coupon#first_order_only` |
| 优惠券折扣封顶 | `Coupon#max_discount_cents` |
| 最近浏览商品 | `store_product_views` + `RecordProductView` |
| 评价图片上传 | `Review#photos` ActiveStorage（最多 3 张） |

### 第二十二轮（论坛 / 商城体验补齐与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 自定义头像上传 UI | `Users/Show.vue` 文件选择与上传 |
| 投票隐藏结果（创建时） | `poll_hide_results_until_vote` + `Topics/New.vue` |
| 帖子书签提醒 | `Bookmarks/Index.vue` 帖子书签备注/提醒 |
| 草稿 Markdown 编辑器 | `Drafts/Edit.vue` + `MarkdownEditor` |
| 草稿定时发布编辑 | `scheduled_at` / `clear_schedule` on draft update |
| 主题页内联书签编辑 | `topicBookmark` + `Topics/Show.vue` |
| 分区热门排序 | `Sections/Show.vue` hot sort |
| 投票截止时间显示 | `serialize_poll` `closes_at` |
| 信任等级进度提示 | `TrustLevel.progress_for` + 资料页 / 私信门槛 |
| 心愿单规格切换修复 | `ToggleWishlist` 更新 variant 而非移除 |
| 到货通知规格库存 | variant-aware `in_stock` + 一键加购 |
| 心愿单单件加购 | `AddWishlistItemToCart` |
| 评价编辑 | `canEditReview` + 表单复用 |
| 最近浏览完整页 | `products#recently_viewed` |
| 优惠券中文错误 | `Coupon#inapplicable_reason` |
| 商品浏览量展示 | `Products/Show.vue` view_count |
| 公开心愿单规格 | `Wishlist/Public.vue` |
| 商品对比（Session） | `ToggleCompare` + `Compare/Show.vue` |
| 评分分布图 | `ratingBreakdown` on product show |
| 商城站内通知 | Q&A 回复 / 到货补货 in_app 渠道 |

### 第二十三轮（论坛 / 商城精细化与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 投票过期维护任务 | `CloseExpiredPollsJob` + `recurring.yml` |
| 预览审查词过滤 | `PreviewsController` 接入 `FilterCensoredWords` |
| 帖子书签内联编辑 | `serialize_post` bookmark 元数据 + `Topics/Show.vue` |
| 编辑主题前缀 | `EditTopic` + 主题编辑 UI |
| 移除自定义头像 | `remove_forum_avatar` + 资料页按钮 |
| 拉黑用户列表 | `BlocksController#index` + `/forum/blocks` |
| 禁言详情展示 | `mute_info` on 个人资料页 |
| 后台手动授徽章 | `Admin::UsersController#grant_badge` |
| 评价编辑保留图片 | `CreateReview` 无新图时不 purge |
| 心愿单规格价格库存 | `WishlistController` variant-aware 序列化 |
| 对比列表计数修复 | `compare_product_count` 仅统计在售商品 |
| 商品页取消到货通知 | `stockAlertUnsubscribeUrls` + 取消按钮 |
| 评分分布可点击筛选 | `Products/Show.vue` 点击星级 |
| 订单站内通知 | `NotifyOrderEvent` 创建/支付成功 |
| 商城错误信息中文化 | `ValidateCartItem` / `CreateReview` 等 |
| 导航补全 | 最近浏览 / 对比 / 商城通知 / 拉黑 |
| 清空浏览记录 | `products#clear_recently_viewed` |
| 对比页规格行 | `Compare/Show.vue` variants 展示 |

### 第二十四轮（论坛 / 商城全链路通知与体验补齐）

| 功能 | 实现 |
|------|------|
| 草稿保存含投票/定时/前缀 | `SaveTopicDraft` + `SyncTopicPoll` + `Topics/New.vue` |
| 定时发布含投票 | `ScheduleTopic` 支持 poll 参数 |
| 未读/关注列表分页排序 | `UnreadController` / `WatchedController` + Pagy + hot 排序 |
| 关注页主题/用户 Tab | `FollowsController` tab + 双分页 |
| 粉丝列表 | `FollowersController` + `/forum/users/:username/followers` |
| Markdown 脚注 | `FormatPostBody` 占位符 + `[^n]` 定义语法 |
| 服务端回复草稿 | `ReplyDraft` + `ReplyDraftsController` + 主题页同步 |
| 订单取消站内通知 | `CancelOrder` → `NotifyOrderEvent` |
| 发货完成站内通知 | `SyncOrderFulfillmentStatus` → `NotifyOrderEvent` |
| 退款申请/完成/拒绝通知 | `RequestRefund` / `ProcessRefund` / `RejectRefund` |
| 弃购购物车 in_app | `AbandonedCartReminderJob` 双渠道 |
| 订单列表再次购买 | `serialize_order_list_item` + `Orders/Index.vue` |
| 下载链接刷新 | `orders#refresh_download` + 订单详情按钮 |
| 商城退款申请偏好 | `commerce.refund_requested` 通知类型 |

### 第二十五轮（论坛 / 商城体验细化与 Bug 修复）

| 功能 | 实现 |
|------|------|
| 草稿编辑投票/前缀 | `Drafts/Edit.vue` + `drafts#update` 传递 poll 参数 |
| 草稿列表投票标识 | `has_poll` badge on `Drafts/Index` |
| 未读按数量排序 | `TopicListSortable` `unread` 排序 |
| 活动流主题 Tab | `ActivityController` tab=posts/topics |
| 关注标签主题流 | `watched#tag_topics` + `Watched/TagTopics.vue` |
| 订单处理中通知 | `FulfillOrderJob` → `commerce.order_processing` |
| 订单发货中通知 | `FulfillOrderJob` → `commerce.order_fulfilling` |
| 购物车更新重置弃购提醒 | `Cart#reset_abandoned_reminder!` |
| 评价编辑保留图片提示 | `Products/Show.vue` 现有图片预览 |
| 评价图片可点击放大 | 评价列表图片链至原图 |

### 第二十六轮（论坛 / 商城社交与交易闭环）

| 功能 | 实现 |
|------|------|
| 活动流关注的人 Tab | `ActivityController` tab=following |
| @提及搜索增强 | 昵称/显示名、双向拉黑过滤、头像展示 |
| 草稿隐藏投票清除 | `Drafts/Edit.vue` 保存时清空 poll |
| 商品问答分页搜索 | `products#show` question_page/question_q |
| 订单完成通知 | `SyncOrderFulfillmentStatus` → `commerce.order_completed` |
| 对比页加入购物车 | `Compare/Show.vue` + `db_id` |
| 导航修复 | `routes.storeWishlist` + 标签主题链接 |

### 第二十七轮（论坛 / 商城精细化体验）

| 功能 | 实现 |
|------|------|
| 拆分主题 | `Community::SplitTopic` + `topics#split` |
| 举报预设原因 | `Report::REASONS` + `reason_code` 迁移 |
| 代码块语法高亮 | `highlight.js` + `lib/highlightCode.ts` |
| 用户资料分页 | `UsersController` topics/posts Pagy + Tab |
| 通知分组与分类 Tab | 按 `order_public_id` 分组 + forum/commerce 筛选 |
| 促销原价 | `compare_at_price_cents` + 列表/详情展示 |
| 价格区间筛选 | `products#index` price_min/price_max |
| 购物车移入心愿单 | `MoveCartItemToWishlist` + `carts#move_to_wishlist` |
| 删除自己的评价 | `DeleteReview` + `reviews#destroy` |
| 已购买徽章 | `products#show` purchased 标记 |

### 第二十八轮（论坛 / 商城体验深化）

| 功能 | 实现 |
|------|------|
| 主题静音 | `TopicMute` + 回复通知过滤 |
| 分区全部已读 | `MarkSectionRead` + `sections#mark_all_read` |
| 相关主题 | `Topic#related_by_tags` 侧边栏 |
| 拆分至目标分区 | `SplitTopic` 可选 `section_slug` |
| 帖子原文 | `posts#raw` 纯文本 Markdown |
| 投票者列表 | `polls#voters` JSON |
| 通知分类全部已读 | `mark_all_read` 支持 category 参数 |
| 促销筛选排序 | `on_sale` 筛选 + `discount_desc` 排序 |
| 折扣百分比徽章 | `discount_percent` / `discount_label` |
| 心愿单促销价 | 列表展示划线价与折扣 |
| 再次购买 | `ReorderProduct` + `products#reorder` |
| 优惠券满减提示 | `PreviewCoupon` 最低消费/差额 |

### 第二十九轮（论坛 / 商城精细化）

| 功能 | 实现 |
|------|------|
| 分区通知静音 | `SectionMute` + `ToggleSectionMute` + `sections#mute` |
| 用户忽略 | `UserIgnore` + `ToggleUserIgnore` + `ignores#create` |
| 锁定原因 | `forum_topics.lock_reason` + 版主锁定弹窗 |
| 禁止自反应 | `ToggleReaction` 校验 + 前端隐藏按钮 |
| 长帖折叠 | `body_long` + 展开/收起 |
| 编辑倒计时 | `edit_seconds_remaining` 展示 |
| 参与者头像条 | `Topic#participant_users` + 分区列表展示 |
| 降价提醒 | `PriceAlert` + `SubscribePriceAlert` + `NotifyPriceDropJob` |
| 清空购物车 | `ClearCart` + `carts#clear` |
| 购物车交叉销售 | 同分类推荐 `crossSellProducts` |
| 商品短描述 | `store_products.summary` 列表/管理表单 |
| 评价举报 | `Commerce::Review` 纳入举报系统 |

### 第三十轮（论坛 / 商城闭环与管理页）

| 功能 | 实现 |
|------|------|
| 降价提醒管理页 | `PriceAlertsController#index/#destroy` + `PriceAlerts/Index.vue` |
| 商品页降价订阅 | `products#show` price_alert 按钮 |
| 降价通知偏好 | `commerce.price_drop` 商城通知设置 |
| 忽略用户列表 | `ignores#index` + `Ignores/Index.vue` |
| 静音管理页 | `mutes#index` 主题/分区静音列表 |
| 前缀筛选 | `TopicFilterable` prefix 选项 + 分区列表 |
| 商品 Onebox | `FetchProductOnebox` + `FormatPostBody` 嵌入卡片 |
| 认证买家徽章 | 帖子 `verified_purchaser` + `first_purchase` 自动徽章 |
| 资料商城 Tab | 用户资料页展示评价与订单数 |

### 第三十一轮（论坛商城深度联动）

| 功能 | 实现 |
|------|------|
| 商品讨论主题 | `store_products.forum_topic_id` + `EnsureProductDiscussionTopic` |
| 主题关联商品卡片 | `Topic#linked_product` + `Topics/Show.vue` |
| 评价分享到论坛 | `ShareReviewToForum` + `reviews#share_to_forum` |
| 成员排行榜排序 | `members#index` posts/likes/reviews/purchases 排序 |
| 订单商品链接与提问 | `Orders/Show.vue` product_url + askFromOrder |
| 公开优惠券页 | `CouponsController` + `Coupons/Show.vue` |
| 主题 bump 冷却 | `forum.bump_cooldown_hours` + `bump_props` |
| 帖子编辑通知 | `NotifyPostEdited` + `forum.post_edited` 偏好 |
| 编辑内联 diff | `DiffLines` → `edit_diff_lines` 序列化 |
| 更新日志通知购买者 | `NotifyProductChangelogJob` + `commerce.product_changelog` |
| 上架自动创建讨论帖 | 管理端 create/update 商品时调用 |

### 第三十二轮（论坛列表完善与商城问答增强）

| 功能 | 实现 |
|------|------|
| 论坛主题 Onebox | `FetchTopicOnebox` + `FormatPostBody` |
| 主题列表最后回复者 | `last_poster_username` + 列表页展示 |
| 主题列表标签/商品徽章 | `TopicTitleBadges` tags + linked_product |
| 列表 N+1 优化 | `TopicListPreloadable` concern |
| 忽略用户过滤通知 | `FilterNotificationRecipients` |
| 购买后自动关注讨论 | `SubscribeProductDiscussion` on payment |
| 订单关联提问修复 | `order_item_id` 前后端贯通 |
| 问答回答有帮助投票 | `ToggleAnswerHelpful` + migration |
| 成员购买数展示 | `purchases_count` 排行榜 |
| 优惠券限制透明化 | per_user_limit / max_discount 公开页 |
| 管理端问答订单列 | admin product_questions order_number |

### 第三十三轮（列表统一与通知补全）

| 功能 | 实现 |
|------|------|
| 主题列表浏览数 | `TopicListTable` + views 列 |
| 统一主题列表组件 | `TopicListTable.vue` 用于分区/最新/标签/关注/未读 |
| 优惠券 Onebox | `FetchCouponOnebox` + `FormatPostBody` |
| 帖子编辑邮件通知 | `ForumMailer#post_edited` |
| 更新日志邮件通知 | `OrderMailer#product_changelog` |
| 通知忽略过滤补全 | followed/tag 通知过滤 |
| Wiki 编辑历史公开 | guests 可访问 `posts#edits` |
| 类似主题扩展 | `similar_topics` 同分区回退 |
| 问答回答排序 | `question_sort=helpful` |
| 员工新提问通知 | `NotifyNewProductQuestion` |
| 资料页订单历史 | 本人 store tab 显示订单 |
| SiteSetting 种子 | bump 冷却 + 商品讨论分区 |

### 第三十四轮（列表补全与商城邮件）

| 功能 | 实现 |
|------|------|
| 参与者头像批量预加载 | `attach_participant_users!` + `serialize_topics` 消除 N+1 |
| 关注标签/关注用户列表统一 | `TagTopics.vue`、`Following/Index.vue` 接入 `TopicListTable` |
| 书签主题富展示 | `TopicTitleBadges` + 浏览数/最后回复 |
| 分区必填标签（XenForo） | `required_tag_ids` + `ValidateSectionRequiredTags` + 管理端多选 |
| 复制帖子链接反馈 | `Topics/Show.vue` 复制后显示「已复制」 |
| 订单处理/发货/完成邮件 | `OrderMailer#order_processing/fulfilling/completed` |
| 反应通知忽略过滤确认 | `NotifyPostReaction` 已接入 `FilterNotificationRecipients` |

### 第三十五轮（XenForo 规则补全与通知邮件）

| 功能 | 实现 |
|------|------|
| 草稿/定时发布必填标签校验 | `PublishTopicDraft` / `PublishScheduledTopic` / `ScheduleTopic` |
| 分区标签白名单 | `allowed_tag_ids` + `SyncTopicTags` 校验 |
| 主题前缀必填 | `prefix_required` + `CreateTopic` 校验 |
| 列表 UI 补全 | 搜索/动态/用户资料接入 `TopicListTable` |
| 用户资料 Onebox | `FetchUserOnebox` + `FormatPostBody` |
| 慢速模式倒计时 UI | `slow_mode_remaining_seconds` + 回复表单禁用 |
| 图片上传信任等级 | `TrustLevel.can_upload_images?` + 前端提示 |
| 书签提醒邮件 | `ForumMailer#bookmark_reminder` |
| 降价/退款申请邮件 | `OrderMailer#price_drop` / `#refund_requested` |

### 第三十六轮（用户警告、礼品卡与阅读体验）

| 功能 | 实现 |
|------|------|
| 用户警告系统（XenForo） | `forum_user_warnings` + `CreateUserWarning` + 管理端 `warn` |
| 警告通知与邮件 | `NotifyUserWarning` + `ForumMailer#user_warning` + 偏好 `forum.user_warning` |
| 资料页警告积分/记录 | `UsersController` + `Users/Show.vue` |
| 主题阅读时间估算（Discourse） | `EstimateReadingTime` + `reading_time_minutes` + `Topics/Show.vue` |
| 礼品卡 | `store_gift_cards` + `ApplyGiftCard` / `PreviewGiftCard` / `DebitGiftCard` |
| 结账礼品卡预览 | `CheckoutController#preview_gift_card` + `Checkout/Show.vue` |
| 订单礼品卡展示 | `serialize_order_detail` + `Orders/Show.vue` |
| 管理端礼品卡 | `Admin::Store::GiftCardsController` + `GiftCards/Form.vue` |
| 书签主题列表统一 | `Bookmarks/Index.vue` 接入 `TopicListTable` |
| 员工新提问邮件 | `NotifyNewProductQuestion` + `OrderMailer#new_product_question` |
| 弃购邮件 HTML | `CartMailer#abandoned_cart.html.erb` |

### 第三十七轮（审核恢复、礼品卡完善与论坛细节）

| 功能 | 实现 |
|------|------|
| 帖子恢复（XenForo undelete） | `RestorePost` + 管理端恢复按钮 |
| 已删除帖子幽灵显示 | 版主可见 `with_discarded` + 删除样式 |
| 编辑原因展示（Discourse） | `last_edit_reason` 内联显示 |
| 反应用户弹层 | `ReactionUsersPopover` 点击查看 |
| 分区主题模板（XenForo） | `topic_template` + 发帖预填 |
| 搜索日期范围 | `created_after` / `created_before` |
| 员工备注 | `forum_staff_notes` + 管理端私有备注 |
| 警告积分阈值自动禁言 | `EnforceWarningThreshold` + SiteSetting |
| 礼品卡退款恢复余额 | `RestoreGiftCardBalance` |
| 零元订单直接确认 | 礼品卡全额抵扣免支付流程 |
| 礼品卡公开页 | `/store/gift_cards/:code` |
| 购物车礼品卡预览 | session 持久化 + 预览 API |
| 礼品卡 Onebox | `FetchGiftCardOnebox` |
| 收据/PDF 优惠明细 | 优惠券 + 礼品卡分行展示 |
| 管理端礼品卡编辑/使用记录 | `edit`/`update` + 订单列表 |
| 修复 `storePreferences` 路由 | `routes.ts` |

### 第三十八轮（举报阈值、订阅级别与商城完善）

| 功能 | 实现 |
|------|------|
| 举报阈值自动隐藏（Discourse） | `CheckReportThreshold` + SiteSetting `forum.report_auto_hide_threshold` |
| 订阅级别 Watching/Tracking | `forum_subscriptions.notification_level` + `ToggleSubscription` 三级循环 |
| 跟踪仅站内通知 | `NotifyTopicReply` 邮件仅 `watching` 级别 |
| 主题回复禁言（XenForo） | `forum_topic_reply_bans` + `BanTopicReply` / `UnbanTopicReply` |
| 主题员工备注 | `forum_topic_staff_notes` + `CreateTopicStaffNote` |
| 分区最低信任等级 | `min_trust_level_create/reply` + Section 校验 |
| PM 会话归档 | `conversation_participants.archived_at` + 归档/恢复 |
| 全站公告横幅 | `global_announcement` + `PortalLayout` 顶栏 |
| 匿名投票 | `forum_polls.anonymous` + 投票者列表隐藏 |
| 礼品卡邮件 | `GiftCardMailer` + 管理端收件人 |
| 礼品卡到期提醒 Job | `GiftCardExpiryReminderJob` |
| 用户礼品卡钱包 | `owner_user_id` + `/store/gift_cards` Index |
| 变体促销原价 | `store_product_variants.compare_at_price_cents` |
| 商城分类公开页 | `Commerce::CategoriesController` |
| 管理端复制商品 | `DuplicateProduct` |
| 低库存员工通知 | `NotifyLowStockStaffJob` |

### 第三十九轮（只读分区、沉默用户与商城流水）

| 功能 | 实现 |
|------|------|
| 分区只读模式（XenForo） | `forum_sections.read_only` + 发帖/回复拦截 |
| 用户沉默（可浏览不可发帖） | `forum_user_silences` + 管理端沉默/解除 |
| 罐头回复（Discourse） | `forum_canned_responses` + 管理端 + 主题回复插入 |
| 撤销投票 | `RevokePollVote` + 投票 UI |
| 分区/标签订阅级别 | `ToggleSectionSubscription` / `ToggleTagSubscription` 三级循环 |
| 分区通知邮件级别 | `NotifySectionTopic` 仅 `watching` 发邮件 |
| 举报驳回自动恢复显示 | `ClearReportableHide` + 管理端 dismiss |
| 礼品卡余额流水 | `store_gift_card_transactions` + 扣款/退款记录 |
| 商城分类描述 | `store_categories.description` + 分类页展示 |
| 用户订单 CSV 导出 | `OrdersController#export` |

### 第四十轮（分区样式、邀请关注与礼品卡商品）

| 功能 | 实现 |
|------|------|
| 分区颜色与图标（Discourse/XenForo） | `forum_sections.color_hex` / `icon` + 管理端 + 分区列表展示 |
| 主题邀请关注（Discourse） | `forum_topic_invites` + `InviteTopicWatcher` + 主题页邀请 UI |
| 邀请通知 | `NotifyTopicInvite` + `forum.topic_invite` 站内通知 |
| 版控小操作帖（XenForo small action） | `post_type: small_action` + `CreateSmallActionPost` + 版控自动记录 |
| 单帖 Wiki 模式 | `forum_posts.wiki` + `ModeratePost` enable/disable + 编辑权限 |
| 搜索高级语法 | `ParseSearchQuery` 解析 `in:分区` / `@用户` / `author:用户` |
| 反应信任等级门槛 | `TrustLevel.can_react?` + SiteSetting `forum.min_trust_level_reaction` |
| 礼品卡商品类型 | `product_type: gift_card` + `FulfillGiftCardItem` 自动发卡 |
| 礼品卡购买邮件 | `GiftCardMailer#gift_card_purchased` |
| 订单礼品卡展示 | `serialize_order_detail` + `Orders/Show.vue` |
| 优惠券最低消费 UI | 结账预览 `min_amount_label` / `amount_remaining_label` |
| 商品 SKU 公开展示 | `Products/Show.vue` 变体 SKU |
| 礼品卡来源订单项 | `store_gift_cards.source_order_item_id` |

### 第四十一轮（未列出主题、标签颜色与礼品卡退款撤销）

| 功能 | 实现 |
|------|------|
| 未列出主题（Discourse unlisted） | `forum_topics.unlisted` + `published_listed` 作用域 + 版控切换 |
| 标签颜色（XenForo） | `forum_tags.color_hex` + 管理端 + 标签页展示 |
| 搜索 tag: 语法 | `ParseSearchQuery` 解析 `tag:标识` |
| 帖子员工提示（XenForo notice） | `forum_posts.staff_notice` + 版控设置/清除 |
| 定时关闭/置顶小操作帖 | `CloseScheduledTopic` / `UnpinExpiredTopicsJob` + `SystemActor` |
| 退款撤销已发礼品卡 | `RevokeIssuedGiftCards` + `ProcessRefund` 联动 |
| 商城分类图标与颜色 | `store_categories.icon` / `color_hex` |
| 优惠券公开说明 | `store_coupons.description` + 详情页展示 |

### 第四十二轮（分类样式、分区公告、运费与心愿单备注）

| 功能 | 实现 |
|------|------|
| 论坛分类颜色与图标（XenForo） | `forum_categories.color_hex` / `icon` + 管理端 + 板块列表展示 |
| 分区公告横幅（Discourse） | `forum_sections.banner_text` + 分区页顶部展示 |
| 搜索 is:solved / is:unsolved | `ParseSearchQuery` + `SearchController` 联动 |
| 解决后自动关闭主题 | SiteSetting `forum.auto_close_on_solved` + `MarkTopicSolved` 小操作帖 |
| 免运费门槛与固定运费 | SiteSetting + `CalculateShipping` + 购物车/结账/订单展示 |
| 订单运费字段 | `store_orders.shipping_cents` + `CreateOrder` / 优惠券礼品卡合计 |
| 心愿单备注（XenForo watch notes） | `store_wishlist_items.note` + `UpdateWishlistNote` |
| 商品对比 SKU 行 | 对比页展示变体 SKU |
| 商城分类导航图标 | `serialize_category` 含 icon/color_hex |

### 第四十三轮（主题状态搜索、缺货预订与对比上限）

| 功能 | 实现 |
|------|------|
| 搜索 is:locked / is:unlocked / is:pinned / is:wiki | `ParseSearchQuery` + `ApplyTopicSearchFilters` |
| 分区主题筛选锁定/置顶/Wiki | `TopicFilterable` 新增筛选项 |
| 论坛分类描述展示 | 管理端 description + 板块首页分类卡片 |
| 商品缺货可预订（Backorder） | `store_products.allow_backorder` + 购物车/下单 |
| 对比列表上限可配置 | SiteSetting `store.compare_max_items` |
| 优惠券公开开始时间 | 优惠券详情页 `starts_at` |

### 第四十四轮（精选/公告搜索、分区外链与最低购买量）

| 功能 | 实现 |
|------|------|
| 搜索 is:featured / is:announcement / is:global | `ParseSearchQuery` + `ApplyTopicSearchFilters` |
| 分区筛选精选与全站公告 | `TopicFilterable` 新增筛选项 |
| 分区外链（Discourse） | `forum_sections.link_url` / `link_label` + 分区页展示 |
| 商品最低购买量 | `store_products.minimum_quantity` + `ValidateCartItem` |
| 购物车限购余量提示 | `PurchaseLimitRemaining` + 购物车项序列化 |

### 第四十五轮（搜索补全、未列出 SEO、商城运费与限购）

| 功能 | 实现 |
|------|------|
| 搜索 is:unlisted / has:poll / has:noreplies | `ParseSearchQuery` + `ApplyTopicSearchFilters` + `SearchController` |
| 未列出主题 noindex（Discourse） | `TopicsController` meta + `Topics/Show.vue` robots |
| 版主分区未列出筛选 | `TopicFilterable` + `SectionsController` |
| 主题邀请通知偏好 | `forum.topic_invite` + `PreferencesController` |
| 成员目录在线筛选 | `MembersController` sort=online + `Members/Index.vue` |
| 信任等级编辑窗口（Discourse） | `TrustLevel.edit_window_for` + `EditPost` |
| 商品最高购买量 | `store_products.maximum_quantity` + `ValidateCartItem` |
| 商品运费开关 | `requires_shipping` + `CalculateShipping` 按购物车计算 |
| 优惠券免运费 | `store_coupons.free_shipping` + `ApplyCoupon` / `PreviewCoupon` |
| 购物车 URL 自动应用优惠码 | `CartsController#show` `?coupon=` 参数 |

### 第四十六轮（用户卡片、保存搜索、商品 SEO 与快捷加购）

| 功能 | 实现 |
|------|------|
| 帖子作者徽章展示（Discourse） | `serialize_user_badges` + `Topics/Show.vue` |
| 用户悬停卡片（Discourse User Card） | `UsersController#card` + `UserHoverCard.vue` |
| 私信内容搜索（XenForo） | `ConversationsController` `?q=` 筛选 |
| 保存论坛搜索 | `forum_saved_searches` + `SavedSearchesController` |
| 商品 SEO 元数据 | `store_products.seo` + 管理端 + `Products/Show.vue` Head |
| 商城 Sitemap | `Commerce::SitemapsController` `/store/sitemap.xml` |
| 结账页 URL 自动应用优惠码 | `CheckoutController` `?coupon=` |
| 商品列表快捷加购 | `quick_addable` + `Products/Index.vue` |
| 购物车总件数上限 | SiteSetting `store.cart_max_items` + `ValidateCartItem` |

### 第四十七轮（阅读进度、转主题、分区默认订阅与商城收货）

| 功能 | 实现 |
|------|------|
| 主题阅读进度条（Discourse） | `ReadingProgress.vue` + `Topics/Show.vue` |
| 回复转新主题（带回溯链接） | `CreateTopicFromPost` + `forum_topics.source_post_id` + `posts#fork_topic` |
| 分区默认通知级别 | `forum_sections.default_notification_level` + `ToggleSectionSubscription` |
| 多选引用回复 | `Topics/Show.vue` 累积多条 quote |
| 分类 SEO 元数据 | `store_categories.seo` + 管理端 + `Categories/Show.vue` Head |
| 订单收货地址 | `store_orders.shipping_address` + 结账表单 + `CreateOrder` |
| 弃购购物车深链 | `store_carts.recovery_token` + 邮件/通知恢复 URL |
| 再次购买跳过原因 | `ReorderFromOrder` 详细 `skipped` + 订单页提示 |

### 第四十八轮（分叉回溯、楼主关帖与商城结账完善）

| 功能 | 实现 |
|------|------|
| 原帖分叉回溯链接（Discourse） | `Post#forked_topics` + `Topics/Show.vue` 衍生主题列表 |
| 楼主关闭/重开主题（XenForo） | `CloseOwnTopic` + `topics#close_own` / `reopen_own` |
| 帖子图片灯箱（Discourse） | `ImageLightbox.vue` 点击放大 |
| 主题回复排序 | `TopicsController` `post_sort` + 最早/最新切换 |
| 选中文字引用（Discourse） | `Topics/Show.vue` 划词引用浮层 |
| 用户卡片增强 | `UsersController#card` bio/获赞/在线状态 |
| 收货地址服务端校验 | `ValidateShippingAddress` + `CreateOrder` |
| 结账页运费展示 | `Checkout/Show.vue` 运费行与免运费提示 |
| 结账地址预填 | 上次订单 `shipping_address` 自动填充 |
| 收据/管理端地址 | `receipt.html.erb` / PDF / 管理订单详情 |
| 商城首页 SEO | SiteSetting `store.seo_title` + `Products/Index.vue` |
| 商品 og:image | `product_seo_props.seo_image` + `Products/Show.vue` |
| 弃购恢复提示横幅 | `cartRecovered` + `Carts/Show.vue` |
| 多选引用移除同步 | 移除引用时同步清理回复正文 |

### 第四十九轮（员工私语、主题分享、配送方式与物流追踪）

| 功能 | 实现 |
|------|------|
| 论坛分类/分区 SEO（Discourse/XenForo） | `forum_categories.seo` / `forum_sections.seo` + 管理端表单 + 分区页 Head |
| 员工私语帖（Discourse whisper） | `forum_posts.whisper` + `CreatePost` 权限校验 + 主题页仅员工可见 |
| 投票编辑（延长关闭时间等） | `EditTopicPoll` + `EditTopic` 联动 + 主题编辑 UI |
| 主题私信分享（Discourse share） | `ShareTopicAsConversation` + `topics#share_as_pm` |
| 论坛键盘快捷键（Discourse） | `ForumShortcuts.vue` + `PortalLayout` 全局监听 |
| 配送方式选择（标准/加急） | `ShippingMethods` + `CalculateShipping` + 结账页选择 |
| 运费与 flat_shipping 兼容 | `store.flat_shipping_cents` 同步标准配送单价 |
| 订单物流追踪 | `store_orders.shipping_method` / `tracking_number` / `shipping_carrier` / `shipped_at` |
| 管理端发货录入 | `UpdateOrderShipping` + 管理订单详情 |
| 发货邮件与装箱单 | `order_shipped` 邮件 + `packing_slip` 打印页 |
| 订单邮件详情增强 | `_order_details` 部分模板复用 |

### 第五十轮（标签同义词、定时提升、礼品包装与对比分享）

| 功能 | 实现 |
|------|------|
| 标签同义词（XenForo） | `forum_tags.canonical_tag_id` + `SyncTopicTags` 归并 + 管理端 |
| 主题定时自动提升（Discourse bump） | `forum_topics.auto_bump_at` + `BumpScheduledTopicsJob` |
| 用户头衔颜色（XenForo flair） | `users.forum_flair_color_hex` + 帖子作者彩色头衔 |
| 投票结果 CSV 导出 | `ExportPollResults` + `polls#export` |
| 订单员工备注（Shop） | `store_order_staff_notes` + 管理端 `staff_note` |
| 管理端买家备注展示 | 订单详情显示 `store_orders.notes` |
| 商品对比分享链接 | `compare_share_token` + `Compare/Public.vue` |
| 结账礼品包装 | `store.gift_wrap_cents` + `CalculateGiftWrap` + 结账勾选 |
| PDF 收据字段增强 | 备注/配送/物流/礼品包装/礼品卡行 |

### 第五十一轮（主题归档、楼层锚点、最低消费与订单 Webhook）

| 功能 | 实现 |
|------|------|
| 「我已解决」筛选（Discourse） | `TopicFilterable#solved_mine` |
| 列表 Wiki/公告/未列出徽章 | `TopicTitleBadges` + `serialize_topic_list_item` |
| 楼层 permalink `#p-{floor}` | `PostPermalink` + 主题页滚动定位 |
| 主题归档/取消归档（Discourse） | `forum_topics.archived_at` + `ModerateTopic` + 可见性规则 |
| `@staff` / `@moderators` 群组提及 | `ProcessMentions::GROUP_MENTIONS` |
| 摘要仅关注内容（Discourse watched） | `users.forum_digest_watched_only` + `SendForumDigest` 过滤 |
| 结账最低消费门槛（Shop） | `store.min_checkout_subtotal_cents` + `CreateOrder` 校验 + 结账页禁用 |
| 弃购二次提醒（72h） | `abandoned_second_reminder_sent_at` + `AbandonedCartReminderJob` |
| 订单状态 Webhook | `store.order_webhook_url` + `DispatchOrderWebhook` |
| 管理端改状态用户通知 | `NotifyOrderStatusChange` + 管理订单更新 |
| 订单页商品 Q&A | 订单详情展示已提交问题 + 快捷提问表单 |

### 第五十二轮（公告关闭、搜索高亮、定时开放与商城 Webhook 增强）

| 功能 | 实现 |
|------|------|
| 归档主题筛选/搜索 `is:archived` | `TopicFilterable` + `ParseSearchQuery` + `[归档]` 徽章 |
| 全站公告可关闭（Discourse） | `dismissed_global_announcement_ids` + `PortalLayout` + `DismissGlobalAnnouncement` |
| 主题 SEO 增强 | `og:url` / `canonical` / `og:image`（首帖图片） |
| 搜索关键词高亮 | `HighlightSearchText` + 帖子结果 `<mark>` |
| 用户卡片快速关注 | `UserHoverCard` + `users#card` follow 字段 |
| 定时自动重新开放 | `auto_open_at` + `OpenScheduledTopicsJob` |
| 配送预计送达天数 | `ShippingMethods` delivery_days + 结账展示 |
| 客户部分退款申请 | `RequestRefund` amount_cents + 订单页金额输入 |
| Webhook HMAC 签名 | `store.order_webhook_secret` + `X-McWeb-Signature` |
| 发货 Webhook `order.shipped` | `UpdateOrderShipping` 触发 |
| 弃购恢复专属优惠码 | `store.abandoned_cart_coupon_code` + 恢复链接 |
| 商家评价回复 | `merchant_reply` + 管理端 + 商品页展示 |

### 第五十三轮（@here 提及、正文标签、分类 RSS 与商城运营增强）

| 功能 | 实现 |
|------|------|
| `@here` 提及主题参与者（Discourse） | `ProcessMentions` + `topic_participants` |
| 正文 `#标签` 自动同步（XenForo） | `ProcessHashtags` + 发帖/编辑接入 |
| 论坛分类 RSS | `rss#category` + `categories/:slug.rss` |
| 论坛分类页 | `categories#show` + `forum_category_path` |
| 分区默认标签预填 | `default_tag_ids` + 发帖页 + 管理端 |
| 主题列表摘要/缩略图 | `excerpt` + `thumbnail_url` + `TopicListTable` |
| 商家回复评价通知 | `NotifyMerchantReviewReply` + 邮件 + 偏好 |
| 退款时间窗口 | `store.refund_window_days` + `RequestRefund` |
| 待支付订单过期可配置 | `store.pending_order_expiry_minutes` + Job |
| 商城分类商品数量 | `serialize_category.product_count` |
| Webhook 含行项目 | `DispatchOrderWebhook` items[] + subtotal |
| 商城通知偏好 | `commerce.merchant_review_reply` |

### 第五十四轮（搜索增强、审核工具与商城运营细节）

| 功能 | 实现 |
|------|------|
| 搜索相关度排序 | `topic_sort`/`post_sort` = `relevance` + `ts_rank` |
| 搜索 `is:mine` / `in:bookmarks` | `ParseSearchQuery` + `SearchController` 用户范围 |
| 搜索自动补全 | `search#suggest` + `Search/Index.vue` 下拉 |
| 通知未读筛选 | `notifications#index` read=unread + UI 标签页 |
| 发帖相似标题提示 | `FindSimilarTitles` + `topics#similar_titles` + `New.vue` |
| 更改帖子作者（Discourse） | `ChangePostAuthor` + 版主操作 |
| 成员信任等级筛选 | `MembersController` trust_level + UI |
| 商品 SKU 搜索 | `ProductsController` join variants |
| 订单取消原因 | `CancelOrder` reason + `OrderEvent` |
| 可配置反应表情 | `forum.reaction_emojis` + `ToggleReaction` |
| 购后评价邀请 | `SendReviewRequest` + Job + 邮件 + 偏好 |
| Webhook 投递日志 | `OrderWebhookDelivery` + Job 记录响应 |

### 第五十五轮（主题指派、地址簿与商城细节）

| 功能 | 实现 |
|------|------|
| 主题指派（Discourse Assign） | `assigned_to` + `ModerateTopic` assign/unassign + 通知 |
| 导出主题帖子 CSV | `ExportTopicPosts` + `topics#export` |
| 搜索 `is:assigned` | `ParseSearchQuery` + `ApplyTopicSearchFilters` |
| 信任等级手动覆盖 | `forum_trust_level_override` + 管理端设置 |
| 收货地址簿 | `ShippingAddress` + CRUD + 结账选择 |
| 商城分类 RSS | `Commerce::RssController#category` |
| 购物车赠言 | `store_cart_items.gift_note` + 订单快照 |
| 退款窗口到期展示 | `refund_window_expires_label` + 订单页 |
| 主题指派通知偏好 | `forum.topic_assigned` |
| 管理端 Webhook 投递记录 | 订单详情 sections |

### 第五十六轮（指派收件箱、搜索扩展与商城 RSS）

| 功能 | 实现 |
|------|------|
| 指派收件箱 `/forum/assigned` | `AssignedController` + 导航徽章 |
| 搜索 `is:unassigned` / `assigned:me` | `ParseSearchQuery` + `assignee_id` 过滤 |
| 搜索 `in:watching` / `in:unread` | `SearchController` 用户范围扩展 |
| 分区列表指派筛选 | `TopicFilterable` assigned/unassigned/assigned_mine |
| 用户资料指派主题 Tab | `users#show` tab=assigned |
| 指派员工选择器 | `mentions#search?staff=1` + `Topics/Show.vue` |
| 成员 TL 筛选尊重覆盖 | `MembersController#apply_trust_level_filter` |
| 商城最新商品 RSS | `store/latest.rss` |
| 收货地址编辑 | `shipping_addresses#update` + `UpsertShippingAddress` |

### 第五十七轮（标签组、商店余额、定时归档与商城运营）

| 功能 | 实现 |
|------|------|
| 标签组（XenForo Tag Groups） | `TagGroup` + `one_per_topic` + 分区必填组 |
| 商店余额钱包 | `store_credit_cents` + 结账抵扣 + 管理端调整 |
| 客户可见订单备注 | `visible_to_customer` + 订单页展示 |
| 主题定时归档 | `auto_archive_at` + `ArchiveScheduledTopicsJob` |
| 警告积分后果 | `CheckWarningRestrictions` 限制发帖/链接/私信 |
| 搜索 `category:` / `has:images` | `ParseSearchQuery` + 同义词标签解析 |
| 分区/标签 Onebox | `FetchSectionOnebox` / `FetchTagOnebox` |
| 商品定时上架/下架 | `available_at` / `unavailable_at` + Job |
| `@here` 通知偏好 | `forum.here` + `ProcessMentions` 门控 |
| 管理端警告列表 | `admin/forum/warnings#index` |

### 第五十八轮（R57 前端补全、钱包页与运营增强）

| 功能 | 实现 |
|------|------|
| 结账商店余额 UI | `Checkout/Show.vue` 余额展示 + 可选抵扣 |
| 商店余额钱包页 | `/store/wallet` + 交易记录 |
| 即将上架商品区 | `Product.upcoming` + 商城首页展示 |
| 分类 Onebox | `FetchCategoryOnebox` + `FormatPostBody` |
| 搜索分类/含图筛选 UI | `Search/Index.vue` 下拉与复选框 |
| 搜索建议同义词标签 | `search#suggest` effective_tag 去重 |
| 管理端警告 CSV 导出 | `warnings#index` format=csv |
| 分区必填标签组 UI | `Sections/Form.vue` + 发帖页提示 |
| 商品定时上下架表单 | `Products/Form.vue` datetime 字段 |
| 结账可关闭余额抵扣 | `use_store_credit` 参数 |

### 第五十九轮（标签色展示、部分退款余额、上架通知与搜索指派）

| 功能 | 实现 |
|------|------|
| 主题列表标签颜色 | `serialize_topic_tag` + `TopicTitleBadges` color_hex |
| 标签组颜色 | `forum_tag_groups.color_hex` + 管理端表单 |
| 部分退款按比例退还余额 | `RestoreStoreCreditPartial` + `store_credit_restored_cents` |
| 即将上架到货通知 | `ProductAvailabilityAlert` + `NotifyProductAvailableJob` |
| 搜索指派筛选 UI | `Search/Index.vue` assigned/assignee 控件 |
| 用户资料页商店余额 | `Users/Show` + `/store/wallet` 链接 |
| 上架通知管理页 | `/store/availability_alerts` |

### 第六十轮（商品预览、部分退款库存、标签组选择与搜索增强）

| 功能 | 实现 |
|------|------|
| 即将上架商品预览页 | `/store/products/:id/preview` + `Preview.vue` |
| 部分退款按比例恢复库存 | `RestoreStockPartial` + `stock_restored_quantity` |
| 搜索高级筛选 UI | bookmarks/watching/unread、mine、locked、wiki、poll、noreplies |
| 商品上架通知偏好 | `commerce.product_available` + 邮件 |
| XenForo 标签组选择器 | `TagGroupPicker` + 发帖页分组点选 |
| 标签云按组展示 | `Tags/Index` 分组 + 标签/组颜色 |
| 主题详情标签颜色 | `Topics/Show` color_hex 样式 |

### 第六十一轮（标签组编辑扩展、优惠券恢复、员工搜索与心愿单）

| 功能 | 实现 |
|------|------|
| 草稿编辑标签组选择器 | `Drafts/Edit` + `SectionTagGroupsSerializable` |
| 主题编辑标签组选择器 | `Topics/Show` 编辑区 `TagGroupPicker` |
| 累计全额退款恢复优惠券 | `RestoreCouponPartial` + `coupon_usage_restored` |
| 搜索精选/公告/归档筛选 | `Search/Index` featured/announcement + 员工 unlisted/archived |
| 员工低库存通知偏好 | `commerce.low_stock` 商城通知设置 |
| 即将上架商品心愿单 | `Wishlist#toggle` 支持 `coming_soon` + 预览页按钮 |

### 第六十二轮（礼品卡部分退款、必填标签组提示、心愿单即将上架）

| 功能 | 实现 |
|------|------|
| 部分退款按比例恢复礼品卡 | `RestoreGiftCardPartial` + `gift_card_restored_cents` |
| 必填标签组前端提示 | `TagGroupPicker` required 标记 + 缺失警告 |
| 标签组色点展示 | `TopicTitleBadges` group_color_hex 圆点 |
| 心愿单即将上架展示 | 徽章 + 预览链接 + 上架时间 |
| 心愿单批量加购跳过未上架 | `AddWishlistToCart` 跳过 `coming_soon` |

### 第六十三轮（必填标签组发布校验、心愿单完善、退款恢复明细）

| 功能 | 实现 |
|------|------|
| 必填标签组发布拦截 | `Section#requires_tags_or_groups?` + `CreateTopic` / `ScheduleTopic` / `PublishTopicDraft` / `PublishScheduledTopic` |
| 主题详情标签组色点 | `Topics/Show` 标签 `group_color_hex` 圆点 |
| 心愿单即将上架通知 | `Wishlist#index` 上架通知订阅按钮 |
| 心愿单备注支持未上架 | `update_note` 允许 `coming_soon` 商品 |
| 公开心愿单即将上架 | `public_show` 预览链接 + `Public.vue` 徽章 |
| 订单退款恢复明细 | `serialize_order_restorations` + `Orders/Show` |
| 搜索全站公告文案 | `Search/Index` 「仅全站公告」 |
| 修复 storeProduct 路由 | `routes.ts` `storeProduct` helper |

### 第六十四轮（警告限制 UX、标签组提交拦截、心愿单对比）

| 功能 | 实现 |
|------|------|
| 警告积分发帖/链接/私信提示 | `WarningRestrictionsSerializable` + 发帖/回复/私信页横幅 |
| 必填标签组前端提交拦截 | `TagGroupPicker` expose + New/Drafts/Show 发布校验 |
| 心愿单商品对比 | `compare_url` / `compared` + 对比列表入口 |
| 管理端退款恢复明细 | 员工订单页「退款恢复明细」区块 |
| 管理端商店余额字段 | 订单详情展示余额抵扣 |

### 第六十五轮（心愿单导入对比、标签组实时禁用、草稿必填校验）

| 功能 | 实现 |
|------|------|
| 心愿单一键导入对比 | `AddWishlistToCompare` + 对比页按钮 |
| 必填标签组实时禁用 | `tagsReady` / `canPublish` 禁用发布与保存按钮 |
| 草稿保存必填组校验 | `SaveTopicDraft` 拦截缺失必填标签组 |
| 对比页可导入数量 | `wishlistImportableCount` 展示 |

### 第六十六轮（空状态引导、链接限制完善、心愿单导入对比对称）

| 功能 | 实现 |
|------|------|
| 对比/心愿单空状态引导 | 空列表 CTA 链到商城、心愿单、对比 |
| 心愿单页一键导入对比 | `wishlistImportCompareUrl` + 导入按钮 |
| 回复/编辑链接实时禁用 | `replyBodyHasBlockedLink` / `editBodyHasBlockedLink` |
| 草稿编辑警告限制 | `Drafts/Edit` 横幅 + `canPublish` |
| 私信链接实时禁用 | `Messages/New` `bodyHasBlockedLink` |
| 草稿发布警告校验 | `PublishTopicDraft` CheckWarningRestrictions |
| 编辑帖子链接校验 | `EditPost` 链接限制 |
| 私信链接服务端校验 | `CreateConversation` 链接限制 |
| 对比导入上限跳过提示 | `AddWishlistToCompare` 满额逐件标记 |
| 对比导入 redirect_back | 心愿单导入后返回来源页 |

### 第六十七轮（分页修复、心愿单筛选、对比差异高亮、sticky 购买栏）

| 功能 | 实现 |
|------|------|
| 评价/搜索分页 prop 修复 | `page-param` 替代错误的 `query-param` |
| 分类页分页修复 | `:pagination` + `:base-path` 替代 `:meta` |
| 发帖页链接实时提示 | `watch` body + `bodyHasBlockedLink` 红色提示 |
| 心愿单 URL 筛选 | `in_stock` / `on_sale` / `coming_soon` / `sort` |
| 对比表差异高亮 | `rowHasDiff` / `cellDiffClass` 琥珀色背景 |
| 商品详情 sticky 购买栏 | `IntersectionObserver` 底部固定加购/收藏/对比 |
| 心愿单备注本地 state | `noteDrafts` 避免直接 mutate props |
| 心愿单重复徽章修复 | 移除重复的「未开售」徽章 |

### 第六十八轮（筛选预设、预览对比、群组私信校验、分类排序）

| 功能 | 实现 |
|------|------|
| 心愿单保存筛选预设 | `WishlistFilterPreset` + CRUD + 芯片 UI |
| 分类页排序 UI | 价格升降 / 最热下拉 |
| 对比仅差异行开关 | `onlyDiffRows` / `visibleRows` |
| 即将上架商品加入对比 | 预览页按钮 + compare 支持 `coming_soon` |
| 对比 session 清理 | 移除已下架商品 ID |
| 群组私信链接/警告校验 | `CreateGroupConversation` + `SendMessage` |
| 群组私信 TL0 / 链接横幅 | `Messages/New` 修复 `canSend` |
| 保存搜索 URL 参数补全 | `SavedSearchesController` 同步 filters |
| 心愿单互斥筛选 | `in_stock` 与 `coming_soon` 互斥 |

### 第六十九轮（私信回复限制、商城筛选 chips、列表对比）

| 功能 | 实现 |
|------|------|
| 私信对话页链接/警告限制 | `Messages/Show` 实时禁用 + 横幅 |
| 对比仅差异行记忆 | `localStorage` `mcweb_compare_only_diff` |
| 商城列表筛选 chips | 当前筛选徽章 + 清除筛选 |
| 商品列表加入对比 | `product_compare_props` + 表格对比按钮 |
| 即将上架区加入对比 | 商城首页 upcoming 对比按钮 |
| 保存搜索集成测试 | POST 返回含 `assigned` 的 URL |

### 第七十轮（搜索分页修复、列表心愿单、群组邀请校验、公开筛选分享）

| 功能 | 实现 |
|------|------|
| 搜索帖子分页修复 | `page-param="post_page"` 替换错误 `query-param` |
| 搜索高级筛选 UI | locked/pinned/wiki/featured/poll/noreplies/assigned 等 |
| 保存搜索筛选同步 | `saveSearch` 含全部高级筛选字段 |
| 商品列表心愿单 | `product_wishlist_props` + 列表/即将上架收藏按钮 |
| 群组添加成员校验 | TL0/禁言/警告用户不可被邀请 |
| 添加成员 UI 限制 | `canAddParticipant` + 群组满员/警告时隐藏表单 |
| 私信对话分页 | `page-param="page"` 显式声明 |
| 公开心愿单筛选 | `public_show` 支持 in_stock/on_sale/coming_soon/sort |
| 筛选预设公开分享 | `public_share_url` + 复制分享链接 |

### 第七十一轮（搜索建议、精选区心愿单、群主邀请限制）

| 功能 | 实现 |
|------|------|
| 搜索建议下拉 | `suggestUrl` + 主题/标签/用户实时建议 |
| 精选/最近浏览 compare+wishlist | 商城首页区块加入对比与收藏按钮 |
| 群主专属邀请 | `forum.group_pm_creator_only_add` SiteSetting |
| 添加成员限制提示 | `addParticipantRestrictedReason` 中文说明 |
| 搜索帖子分页集成测试 | `post_page=2` 端到端验证 |

### 第七十二轮（保存搜索每日提醒、建议键盘导航、分类/浏览页心愿单）

| 功能 | 实现 |
|------|------|
| 保存搜索每日邮件提醒 | `notify_daily` + `last_notified_at` 迁移 |
| 保存搜索匹配服务 | `SavedSearchMatcher` 按筛选与关键词匹配新主题 |
| 每日摘要任务 | `SavedSearchDigestJob` + `recurring.yml` 每天 9am |
| 摘要邮件 | `ForumMailer#saved_search_digest` |
| 搜索建议键盘导航 | ↑↓ Enter Esc + 高亮当前项 |
| 保存搜索 UI | `saveNotifyDaily` 复选框 + 已保存项 📧 标记 |
| 最近浏览 compare+wishlist | `RecentlyViewed/Index` 对比/收藏按钮 |
| 分类页 compare+wishlist | `Categories/Show` 对比/收藏 + 筛选 chips |
| 群主设置种子 | `db/seeds.rb` 默认 `forum.group_pm_creator_only_add` |

### 第七十三轮（论坛设置后台、偏好页搜索提醒、分类页筛选对齐）

| 功能 | 实现 |
|------|------|
| 管理后台论坛设置 | `Admin::Forum::SettingsController` 专用 UI |
| 群主邀请策略 | `forum.group_pm_creator_only_add` 复选框 + 中文说明 |
| 保存搜索 PATCH | `notify_daily` 开关更新 |
| 偏好页保存搜索 | 列表展示 + 每日邮件切换 |
| 分类页价格筛选 | `price_min` / `price_max` 后端筛选 |
| 分类页筛选 chips | 与商城首页一致的筛选表单与徽章 |

### 第七十四轮（商城设置后台、搜索提醒切换、偏好页删除、分类排序对齐）

| 功能 | 实现 |
|------|------|
| 管理后台商城设置 | `Admin::Store::SettingsController` 运费/对比/SEO 等 |
| 搜索页提醒切换 | 已保存搜索 📧 按钮一键开关 `notify_daily` |
| 偏好页删除搜索 | `delete_url` + 删除按钮 |
| 分类页排序对齐 | `rating` / `discount_desc` 与商城首页一致 |

### 第七十五轮（搜索重命名、配送方式编辑、摘要邮件管理链接、分类 newest 排序）

| 功能 | 实现 |
|------|------|
| 保存搜索内联重命名 | 搜索页 ✎ 按钮 + PATCH `name` |
| 配送方式 JSON 编辑 | 商城设置 `store.shipping_methods` 文本域 + 校验 |
| 摘要邮件管理链接 | `saved_search_digest` 链接至通知偏好页 |
| 分类页 newest 排序 | `sort=newest` 与商城首页参数统一 |
| 配送方式种子 | `db/seeds.rb` 默认 JSON |

### 第七十六轮（搜索上限、邮件一键退订、偏好页重命名、配送可视化）

| 功能 | 实现 |
|------|------|
| 保存搜索数量上限 | `forum.saved_search_limit` + 模型校验 + 搜索页计数 |
| 摘要邮件一键退订 | `SavedSearchUnsubscribeToken` + 签名链接 |
| 偏好页搜索重命名 | 与搜索页一致的内联 ✎ 重命名 |
| 配送方式可视化 | 商城设置表单编辑 + `stored_list` |
| 论坛设置上限配置 | 管理后台 `forum.saved_search_limit` |

### 第七十七轮（筛选摘要邮件、保存搜索 RSS、结账送达预估、摘要发送时间）

| 功能 | 实现 |
|------|------|
| 摘要邮件筛选 chips | `SavedSearchFilterSummary` + digest 模板展示 |
| 保存搜索 RSS | `SavedSearchRssToken` + `RssController#saved_search` |
| 搜索/偏好页 RSS 链接 | `SavedSearchPresenter.rss_path` + 前端 RSS 按钮 |
| 结账配送预计送达 | `selectedShippingEstimate` 展示所选方式 `delivery_estimate` |
| 摘要发送时间配置 | `forum.saved_search_digest_hour` + 每小时任务检查 |
| 序列化复用 | `SavedSearchPresenter` 统一 url/rss 参数 |

### 第七十八轮（筛选匹配修复、OPML、Webhook、论坛摘要退订、管理设置补全）

| 功能 | 实现 |
|------|------|
| 保存搜索筛选完整匹配 | `BuildSavedSearchTopicScope` 对齐搜索页全部筛选条件 |
| 保存搜索 OPML 导出 | `SavedSearchOpmlToken` + `RssController#saved_searches_opml` |
| 保存搜索 Webhook | `webhook_url` 字段 + `DispatchSavedSearchWebhook` |
| 论坛摘要 HTML + 退订 | `digest.html.erb` + `ForumDigestUnsubscribeToken` |
| 论坛摘要发送时间 | `forum.digest_hour` + 每小时任务检查 |
| 论坛管理设置补全 | `forum.allow_op_close` / `forum.min_trust_level_reaction` |
| 商城 Webhook URL 管理 | 管理后台 `store.order_webhook_url` |
| 订单邮件送达预估 | `_order_details` 展示 `delivery_estimate_label` |

### 第七十九轮（Webhook 投递日志、关注 OPML、搜索建议增强、发货物流链接）

| 功能 | 实现 |
|------|------|
| Webhook 投递日志 | `SavedSearchWebhookDelivery` + Job 记录响应 |
| 偏好页投递记录 | `savedSearchWebhookDeliveries` 最近 20 条 |
| 关注订阅 OPML | `WatchingOpmlToken` + `RssController#watching_opml` |
| 搜索建议增强 | 分区 + 保存的搜索自动补全 |
| 发货邮件物流链接 | `Commerce::TrackingUrl` + `order_shipped` 可点击查询 |
| 物流 URL 复用 | `InertiaSerializable` 委托 `TrackingUrl` |

### 第八十轮（Webhook 重试、管理投递日志、物流时间线、搜索实时刷新）

| 功能 | 实现 |
|------|------|
| Webhook 请求体存储 | `forum_saved_search_webhook_deliveries.request_payload` |
| Webhook 手动重试 | `RetrySavedSearchWebhook` + 偏好页「重试发送」 |
| 管理后台投递日志 | `Admin::Forum::WebhookDeliveriesController#index` + 状态筛选 |
| 订单物流时间线 | `Commerce::OrderShippingTimeline` + 订单详情进度条 |
| 搜索实时刷新 | 搜索页输入 ≥2 字后 450ms 防抖自动 `router.get` |

### 第八十一轮（仅标题搜索、Webhook 自动重试、管理详情、商城投递日志）

| 功能 | 实现 |
|------|------|
| 仅标题搜索 | `title_only` 参数 + `in:title` 语法 + 搜索页复选框 |
| Webhook 自动重试 | Job 指数退避最多 3 次 + `RetryFailedSavedSearchWebhooksJob` 清理超时 pending |
| 论坛投递详情 | `Admin::Forum::WebhookDeliveriesController#show` + 管理重试 |
| 商城投递日志 | `Admin::Store::WebhookDeliveriesController#index` + `request_payload` |
| 物流时间线修复 | 已送达订单正确标记「运输中」完成 |
| 管理列表增强 | 状态 Tab 筛选 + 分页 + 行链接详情 |

### 第八十二轮（Webhook HMAC、仅帖子搜索、商城详情重试、事件筛选、分享链接）

| 功能 | 实现 |
|------|------|
| 论坛 Webhook HMAC | `forum.saved_search_webhook_secret` + `WebhookSignature` |
| 仅帖子搜索 | `posts_only` + `in:posts` + 与仅标题互斥 |
| 搜索链接分享 | 搜索页「复制链接」按钮 |
| 商城 Webhook 详情 | `Admin::Store::WebhookDeliveriesController#show` + 重试 |
| 管理事件筛选 | 论坛/商城 Webhook 列表 `eventTabs` |

### 第八十三轮（即时搜索 RSS、主题高亮、Webhook 统计、批量重试）

| 功能 | 实现 |
|------|------|
| 即时搜索 RSS | `Community::SearchRssToken` + `GET search.rss` + 搜索页 RSS 链接 |
| 搜索主题高亮 | `serialize_topic` 增加 `title_html` + `TopicListTable` 渲染 |
| 帖子高亮修复 | 搜索页帖子结果使用 `body_html` 而非纯文本 |
| Webhook 投递统计 | `WebhookDeliveryStats` 24h 成功率 + 管理仪表盘卡片 |
| 批量重试失败 Webhook | `BulkRetrySavedSearchWebhooks` / `BulkRetryOrderWebhooks` + 管理列表按钮 |

### 第八十四轮（搜索 OPML、Webhook 告警、关注邮件模式、日期筛选）

| 功能 | 实现 |
|------|------|
| 即时搜索 OPML | `GET search.opml` + 搜索页 OPML 链接 |
| Webhook 失败邮件告警 | `WebhookFailureAlertCheck` + `WebhookFailureAlertJob` + 论坛设置阈值/邮箱 |
| 关注即时邮件模式 | `forum_watch_email_mode`（instant/digest_only/none）+ `WatchEmailDelivery` |
| 管理 Webhook 日期筛选 | `created_from` / `created_to` + `Admin::WebhookDeliveryFilterable` |
| 仪表盘失败链接 | 预筛选近 24h 失败投递 + 关注 OPML 含主题订阅 |

### 第八十五轮（搜索历史、摘要已读、Webhook 测试、分渠道告警）

| 功能 | 实现 |
|------|------|
| 搜索历史 | `Community::SearchHistory` + 记录/展示/单删/清空 |
| 摘要标记已读 | `SendForumDigest` 发送后标记通知 `read_at` |
| 商城 Webhook 测试 | `DispatchTestOrderWebhook` + 商城设置页测试按钮 |
| 分渠道告警阈值 | `webhook.failure_alert_forum_threshold` / `store_threshold` |
