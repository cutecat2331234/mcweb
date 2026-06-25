# CHANGELOG

## Unreleased

### Added

- XenForo 对齐:**用户头衔阶梯**——后台按发帖数配置自动头衔(自定义头衔优先);新增 `users.forum_posts_count` 计数缓存,资料页/楼层展示生效
- XenForo 对齐:**公告横幅(Notices)**——后台 CRUD,按样式(info/success/warning/danger)、受众(所有人/会员/访客)、信任等级区间投放,可关闭(登录用户服务端记忆)
- XenForo 对齐:**论坛统计后台**——主题/帖子/会员/反应/已解决等指标 + 发帖最多/最新会员榜
- XenForo 对齐:**奖杯积分(Trophy points)**——按徽章等级(铜/银/金)计分,资料页 + 用户卡展示
- XenForo 对齐:**管理团队页**(`/forum/staff`)——列出拥有后台权限的管理/版主,含在线状态与负责模块
- XenForo 对齐:**论坛首页统计小部件**——板块页底部展示主题/帖子/会员/在线数 + 最新会员
- XenForo 对齐:**楼层作者信息(postbit)**——每个帖子作者名旁显示发帖数 + 加入时间
- XenForo 对齐:**签名后台设置 + 隐藏签名偏好**——后台启用/长度/信任等级限制,用户可在偏好页隐藏他人签名
- XenForo 对齐:**书签标签**——书签可加标签并按标签筛选
- 论坛「热门」(Top)视图:按时间窗口(今日/本周/本月/本季度/今年/全部)排行的高参与度主题列表(对标 Discourse Top),窗口内按常规回帖数排名(排除员工私语/系统动作),导航新增入口,附带按时间段的 RSS 订阅(`/forum/top.rss?period=`)
- 论坛「新主题」(New)列表:展示窗口期内创建、当前用户尚未打开的主题(对标 Discourse New),支持「忽略全部新主题」(尊重当前筛选)、静音主题/分区与已读主题自动排除;窗口天数走 `forum.new_topic_window_days`(默认 14);导航栏「新主题」附未读计数红点(`Topic.unseen_for` 复用于列表/dismiss/计数)
- 论坛「被链接」通知(对标 Discourse linked):帖子/新主题正文链接到其他主题时,通知被链接主题的楼主;站内通知、可在偏好页开关(`forum.linked`),含可见性/拉黑过滤、去重、unlisted 源主题守卫

### Changed

- 用户面板（论坛、商城、登录）统一迁移至 `/app/*` 路径，旧路径自动 301 重定向
- 官网 CMS 页面支持 `/home`、`/about` 等简洁路径；博客改为 `/blog`
- 默认官网模板样式全面升级：导航、首页、CMS 页面块渲染

### Previously

- 生产与 CI 统一使用 PostgreSQL 18；`bin/install` 通过 PGDG 官方源安装 `postgresql-18`

### Fixed

- 管理员只读订单权限不再允许直接修改订单状态
- 封禁/删除用户后立即失效全部 session，登录拒绝已删除账号
- Stripe/Fake webhook 未配置 secret 时拒绝验签（生产环境 Fake 必须配置密钥）
- 邮箱验证链接 24 小时过期

### Previously

- 已取消/不可支付订单拒绝支付确认，避免 payment 误标 succeeded
- CreateOrder 锁定购物车防止并发空单/重复下单
- FulfillOrderJob / FulfillGiftCardItem 加锁防止重复履约
- 零元订单允许 amount_cents 为 0 的支付记录
- ProcessRefund 加锁防止并发重复退款

### Previously

- 限购统计包含 pending 订单，防止多单绕过商品限购
- 礼品卡领取加锁，防止并发重复绑定
- 支付确认前扣减礼品卡余额，余额不足则支付失败
- 注册/重置密码要求至少 6 位密码

### Previously

- 注册后不再自动登录，需先验证邮箱
- 礼品卡 preview API 不再返回 balance_cents
- 未列出主题的 @提及 不再通知非作者/版主
- 举报不可见主题/帖子时统一返回 Content not found
- ApplyCoupon 加锁防止 usage_limit 并发竞态

### Previously

- 礼品卡详情页仅持卡人可见余额
- 优惠券首单/每人限次统计包含 pending 订单，防止多单绕过
- 已支付订单不可再次发起 checkout
- 下载跳转与预览/onebox 图片 URL 需通过 public_http_url 校验

### Previously

- 礼品卡 pending 订单预留余额，防止多张 pending 订单重复抵扣
- 帖子礼品卡 onebox 不再泄露卡号与余额
- 书签页隐藏帖不再展示正文摘要
- 回复/草稿接口对不可见主题统一返回 404
- 链接预览 HTTP 请求固定 DNS 解析 IP，降低 SSRF 重绑定风险

### Previously

- 未读列表/计数、书签、全站公告过滤未列出主题
- 未列出主题的回复/编辑通知不再推送；通知列表对订阅者脱敏

### Previously

- 主题 onebox 不再展示未列出主题
- 分叉主题来源信息与 fork 列表按可见性过滤
- 通知发送与展示校验主题可见性，隐藏主题不再向无权限用户推送或展示内容
- 关注列表过滤未列出主题；无法访问隐藏主题的用户不可被邀请

### Previously

- 动态流/用户资料页过滤隐藏或未列出主题下的帖子
- RSS 与主题页 meta 描述仅使用已发布帖子内容
- 标记已解决校验帖子可读性

### Previously

- 主题页对普通用户仅展示已发布帖子，禁止引用/回复隐藏帖
- 新增 `PostAccess`，隐藏帖子对普通用户不可读/不可互动（raw、反应、书签等）
- 结账未知支付方式不再向用户暴露内部异常信息

### Previously

- `CreatePost` 与 `SaveReplyDraft` 增加主题可见性校验，防止向隐藏/草稿主题回复
- UrlSafety 拒绝云元数据 IP `169.254.169.254`

### Previously

- 统一 `PollParticipation.visible?` 与 `TopicVisibility`，隐藏主题作者可正常访问自己的内容
- `CreateTopicFromPost` / `RestorePostEdit` / 删帖增加主题可见性校验，防止引用隐藏帖内容泄露

### Previously

- 帖子 raw/edits 与 EditPost 统一校验主题可见性，修复草稿与隐藏主题内容泄露
- 投票者列表、帖子反应与书签操作校验主题可见性，防止隐藏主题信息泄露
- UrlSafety 拒绝 IPv6 回环地址 `[::1]`
- 购物车更新失败时不再向用户暴露内部异常信息

### Previously

- 通知跳转 `visit` 使用 `SafeRedirect`，拒绝 metadata 中的开放重定向
- 投票/撤销投票校验主题可见性与分区权限，防止隐藏主题 IDOR
- 商品 `image_url` / `gallery_urls` 模型校验与前端序列化过滤危险 URL

### Previously

- `UrlSafety.safe_image_src?` 统一校验帖子/onebox 图片 URL，修复商品 onebox 与头像的 XSS 风险
- `store_return_location` 写入 session 前过滤协议相对路径等不安全跳转
- `FetchLinkPreview` 缓存预览图前过滤非 http/https URL
- Connector API 认证失败显式 `false` 终止 filter chain
- 移除重复的 `ostruct` gem，消除测试中的常量重复加载警告

### Previously

- 新增 `SafeRedirect`，修复购物车 `referer` 与登录 `return_to` 的开放重定向
- 论坛 onebox 预览图仅允许 `http/https`，拒绝 `javascript:` 等危险 scheme
- `FetchLinkPreview` 发起 HTTP 前二次校验 URL，降低 DNS rebinding 风险
- 清理 Connector 签名中已无用的无时间戳分支

### Previously

- UrlSafety 拒绝空 DNS 结果、CGNAT 地址（100.64.0.0/10）及带凭据的 URL
- Minecraft Connector 认证必须提供有效时间戳，防止重放

### Previously

- 论坛链接预览增加 SSRF 防护，阻止访问 localhost/内网/metadata 地址
- 未验证邮箱的用户无法登录
- `bin/install` rsync 排除 `node_modules` 等目录，避免跨平台依赖污染
- 添加 `ostruct` gem，消除 Ruby 4.0 弃用警告

### Previously

- Minecraft 后台服务器列表/详情改用 `address` 字段，修复 `NoMethodError: host`
- 注册与密码重置通过 `Identity::Mailer` 发送邮件
- 补充 `config/templates/install.env.example`
- `bin/setup` 在开发/测试环境保留 test gem，并自动 `npm ci`
- `bin/install` 支持 `--unattended`、安装 Node.js 并自动运行 setup

