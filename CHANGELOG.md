# CHANGELOG

## Unreleased

### Changed

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

