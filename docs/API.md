# REST API（v1）

McWeb 提供带权限范围控制的 REST API（`/api/v1`），供插件、外部集成或前端读取论坛数据并执行受控写入。所有响应为 JSON。

## 认证

每个请求需携带 API 密钥，两种方式任选其一：

```
Authorization: Bearer mcw_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

或：

```
X-Api-Key: mcw_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

密钥仅在创建时明文返回一次，服务端只保存其 SHA-256 摘要。缺失或无效密钥返回 `401`；被吊销的密钥同样返回 `401`。

### 生成密钥

可在后台的“系统 → API 密钥”页面生成，也可通过 Rails 控制台生成：

```ruby
record, token = Administration::ApiKey.generate!(name: "My integration", scopes: %w[read])
puts token   # => mcw_...  仅此一次可见
```

- `scopes`：支持 `read`、`write` 及下文工作人员工作台的细粒度 scope，必须至少选择一个。缺少所需 scope 返回 `403 insufficient_scope`。
- `user:`：可选。绑定后 API 以该用户的可见范围读取内容；不绑定则按**游客**可见范围（仅公开内容）。
- 吊销：`record.revoke!`。

`read` 密钥绑定用户后可读取该用户有权访问的个人资料、通知和私信，应当像登录会话凭据一样妥善保管。除站点所有者外，后台操作者只能将密钥绑定到自己；已封禁或删除用户的密钥不可使用。

## 限流

按密钥限流，默认 **120 次/分钟**（`SiteSetting` 键 `api.rate_limit_per_minute` 可调）。超限返回 `429 rate_limited`。

## 可见性

API 严格复用站点的分区可见性规则：需要登录的分区（`login_required`）与有 `view` 权限限制的分区，
对游客密钥不可见，其主题/帖子也不会出现在任何列表或详情中。

## 分页

列表端点支持 `?page=`（默认 1）与 `?limit=`（默认 25，最大 100），并在 `meta` 返回分页信息。

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1` | API 自描述（版本、当前密钥 scope/用户、事件目录、可用资源） |
| GET | `/api/v1/me` | 当前密钥绑定用户的资料（未绑定用户返回 `403 no_bound_user`） |
| GET | `/api/v1/notifications?unread=true` | 绑定用户的通知列表（需绑定用户） |
| POST | `/api/v1/notifications/:id/read` | 标记单条通知已读（需 `write`） |
| POST | `/api/v1/notifications/read_all` | 标记全部通知已读（需 `write`） |
| GET | `/api/v1/conversations` | 绑定用户的私信会话列表（需绑定用户） |
| GET | `/api/v1/conversations/:id?mark_read=true` | 会话详情 + 分页消息；`mark_read=true` 另需 `write` |
| POST | `/api/v1/conversations/:id/reply` | 在会话内回复（需 `write` scope） |
| POST | `/api/v1/conversations/:id/read` | 标记会话已读（需 `write`） |
| GET | `/api/v1/categories` | 分类及其可见分区 |
| GET | `/api/v1/tags` | 可用标签（非同义词、对该密钥可见） |
| POST | `/api/v1/tags/:id/subscription` | 关注标签 `level=...`（需 `write`，`:id` 为 slug） |
| GET | `/api/v1/topics?section_id=<slug>&q=<关键词>` | 主题列表（可按分区 slug 过滤、按标题全文搜索） |
| GET | `/api/v1/topics/:id` | 主题详情 + 分页帖子（`:id` 为主题 `public_id`） |
| GET | `/api/v1/posts/:id` | 单帖详情（`:id` 为帖子数值 id） |
| GET | `/api/v1/posts/:id/reactions` | 帖子反应计数 + 允许的表情 |
| POST | `/api/v1/posts/:id/react` | 切换帖子反应 `emoji=...`（需 `write`） |
| GET | `/api/v1/users?q=<名>&sort=<posts\|username\|newest>` | 会员列表（按用户名搜索 / 排序） |
| GET | `/api/v1/users/:id` | 公开用户资料（`:id` 为用户 `public_id`） |
| POST | `/api/v1/users/:id/follow` | 关注/取消关注用户（需 `write`） |
| GET | `/api/v1/users/:id/profile-posts` | 用户资料墙帖子 |
| POST | `/api/v1/users/:id/profile-posts` | 在用户资料墙发帖（需 `write`） |
| POST | `/api/v1/topics` | 发主题（需 `write` scope + 绑定用户） |
| POST | `/api/v1/posts` | 发回帖（需 `write` scope + 绑定用户） |
| GET | `/api/v1/bookmarks` | 绑定用户的书签列表 |
| POST | `/api/v1/topics/:id/bookmark` | 切换主题书签（需 `write`） |
| POST | `/api/v1/topics/:id/subscription` | 设置关注级别 `level=watching\|tracking\|normal\|off`（需 `write`） |
| POST | `/api/v1/topics/:id/solve` | 标记最佳答案 `post_id=...`（需 `write`） |
| POST | `/api/v1/topics/:id/unsolve` | 取消标记（需 `write`） |

## 工作人员治理接口

`/api/v1/staff` 是现有 Rails 领域服务的外部适配层，不是另一套业务实现。网页工作台、后台和外部接入共同复用审核可见性、操作预览、签名确认、乐观锁、幂等记录与审计日志。

工作人员接口必须绑定一个有效用户。所有工作人员写 scope 都同时要求 `staff.moderation.read`。API scope 只决定集成可以调用哪类接口；最终可见的板块、举报、证据和可执行操作仍由绑定用户的版主范围、身份组权限及账号状态决定。它不会因为持有 API 密钥而获得站点管理员权限。

| Scope | 能力 |
|------|------|
| `staff.moderation.read` | 读取自描述入口、可见审核队列和详情 |
| `staff.moderation.claim` | 领取可管理的审核事项 |
| `staff.moderation.assign` | 在有权处理同一事项的工作人员之间转派 |
| `staff.moderation.note` | 写入仅工作人员可见的内部备注 |
| `staff.moderation.execute` | 获取操作预览并执行经过签名确认的治理操作 |

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/staff` | 能力、资源、并发与确认契约自描述 |
| GET | `/api/v1/staff/moderation-cases` | 审核队列；支持普通分页和工作台筛选参数 |
| GET | `/api/v1/staff/moderation-cases/:id` | 审核详情、受权限裁剪的证据、内部备注和可转派人员 |
| POST | `/api/v1/staff/moderation-cases/:id/claim` | 领取事项；提交 `lock_version` |
| POST | `/api/v1/staff/moderation-cases/:id/assign` | 转派或取消转派；提交 `lock_version` 与 `assignee_id` |
| POST | `/api/v1/staff/moderation-cases/:id/notes` | 添加内部备注；提交 `lock_version` 与 `body` |
| POST | `/api/v1/staff/moderation-cases/authorize-action` | 生成影响预览、短期签名令牌和输入确认文本 |
| POST | `/api/v1/staff/moderation-cases/execute-action` | 使用同一请求内容、签名令牌和确认文本执行操作 |

列表筛选支持 `source_kind`、`status`、`priority`、`risk_level`、`section_id`、`assignee_id`、`from` 与 `to`。其中 `assignee_id=me` 表示绑定用户自己，`assignee_id=unassigned` 表示无人领取。

领取、转派和备注必须提交详情中的最新 `lock_version`；版本过期返回 `409`。高影响操作分为授权预览和执行两步，两步应复用一个 1–128 字符的 `request_id`，也可以通过 `Idempotency-Key` 请求头提供。执行请求必须原样提交授权响应的 `authorization_token` 和 `typed_confirmation`。网络重试应复用同一幂等键；将同一键用于不同操作会被拒绝。

### 写入端点

写入端点要求密钥具备 `write` scope **且**绑定了用户（`user:`）——所有写操作都以该用户身份执行，
从而复用既有领域服务（`Community::CreateTopic` / `Community::CreatePost`）的权限、信任等级与防刷限制。
缺少 `write` scope 返回 `403 insufficient_scope`；有 scope 但未绑定用户返回 `403 write_requires_user`；
领域服务校验失败（如标题为空、发帖过快）返回 `422 unprocessable` 并在 `message` 给出原因。

- 创建主题或回复时应发送 `Idempotency-Key` 请求头。键必须为 1–128 个字母、数字、点、下划线、
  冒号或连字符；网络重试必须复用同一个键。
- 同一用户以相同键重试相同请求时，API 返回第一次创建的资源，不会重复创建内容、附件关联、
  通知、积分或 Webhook。把同一个键用于不同内容会返回 `422`。
- 响应会回显有效的 `Idempotency-Key` 请求头。

- `POST /api/v1/topics`：`section_id`（分区 slug）、`title`、`body`、`tag_names[]`（可选）、`prefix`（可选）
- `POST /api/v1/posts`：`topic_id`（主题 public_id）、`body`、`quoted_post_id`（可选）、`parent_post_id`（可选）

### 示例

```bash
curl -H "Authorization: Bearer $MCWEB_API_KEY" \
     "https://your-site.example/api/v1/topics?section_id=announcements&limit=10"
```

```json
{
  "data": [
    {
      "id": "topic_ab12cd34ef56gh78",
      "title": "欢迎",
      "prefix": null,
      "replies_count": 3,
      "views_count": 42,
      "pinned": true,
      "locked": false,
      "solved": false,
      "wiki": false,
      "author": { "id": "usr_...", "username": "admin", "display_name": "Admin" },
      "created_at": "2026-07-01T12:00:00Z",
      "last_posted_at": "2026-07-02T09:30:00Z",
      "tags": [],
      "section_id": "announcements"
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "limit": 10, "prev": null, "next": null }
}
```

## 错误

| 状态码 | `error` | 含义 |
|--------|---------|------|
| 401 | `invalid_api_key` | 密钥缺失/无效/被吊销 |
| 403 | `insufficient_scope` | 密钥缺少所需 scope |
| 404 | `not_found` | 资源不存在或对该密钥不可见 |
| 429 | `rate_limited` | 超出限流 |

## 支付 Webhook 与晚到支付运维契约

以下端点不属于公开 `/api/v1`，不能使用 API 密钥访问：

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/app/store/webhooks/:provider` | 支付渠道 Webhook；Stripe 的事件 ID 和类型只从已签名原始请求体读取 |
| GET | `/admin/store/late-payment-cases` | 晚到支付人工队列；要求后台会话、商城模块和 `store.payments.late_review` 权限 |
| PATCH | `/admin/store/late-payment-cases/:id/acknowledge` | 记录人工复核结果；要求同一专属权限 |

Stripe 的成功事件通过官方签名验证，并完成支付对象、订单、金额、币种和 test/live
环境校验后，如果本地订单已取消或支付窗口已过期，系统会在同一数据库事务内：

1. 保存已成功付款的支付记录；
2. 以 payment record 唯一约束写入 `payment_late_payment_cases`；
3. 保存触发入队的已验证 Webhook 事件关联。

因此事件重试不会重复入队，队列写入失败也不会只留下孤儿 metadata。此类已可靠入队的
Webhook 会正常完成，不会作为未知处理失败进入死信。

人工确认请求必须提交：

- `token`：服务端签发、十分钟内有效并绑定队列、支付、订单和 Webhook 的确认令牌；
- `confirmation`：必须与完整订单号一致；
- `disposition`：服务端允许列表中的后续处置类别；
- `note`：10–1000 字符的复核依据。

确认只把队列状态改为 `acknowledged` 并写入不可变 `AuditLog`，不会自动修改订单、
支付、退款、站内余额或渠道资金。支付引用与事件引用在后台页面中仅以掩码形式显示，
原始 Webhook 载荷、metadata、渠道凭证和客户资料不会返回到页面。
