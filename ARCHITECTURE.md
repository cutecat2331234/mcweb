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
