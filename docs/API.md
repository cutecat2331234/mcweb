# 公开 REST API（v1）

McWeb 提供只读的公开 REST API（`/api/v1`），供插件、外部集成或前端消费论坛数据。所有响应为 JSON。

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

当前通过 Rails 控制台生成（后台管理 UI 可后续加入）：

```ruby
record, token = Administration::ApiKey.generate!(name: "My integration", scopes: %w[read])
puts token   # => mcw_...  仅此一次可见
```

- `scopes`：目前支持 `read`（`write` 预留）。缺少所需 scope 返回 `403 insufficient_scope`。
- `user:`：可选。绑定后 API 以该用户的可见范围读取内容；不绑定则按**游客**可见范围（仅公开内容）。
- 吊销：`record.revoke!`。

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
| GET | `/api/v1/me` | 当前密钥绑定用户的资料（未绑定用户返回 `403 no_bound_user`） |
| GET | `/api/v1/notifications?unread=true` | 绑定用户的通知列表（需绑定用户） |
| POST | `/api/v1/notifications/:id/read` | 标记单条通知已读 |
| POST | `/api/v1/notifications/read_all` | 标记全部通知已读 |
| GET | `/api/v1/conversations` | 绑定用户的私信会话列表（需绑定用户） |
| GET | `/api/v1/conversations/:id?mark_read=true` | 会话详情 + 分页消息 |
| POST | `/api/v1/conversations/:id/reply` | 在会话内回复（需 `write` scope） |
| POST | `/api/v1/conversations/:id/read` | 标记会话已读 |
| GET | `/api/v1/categories` | 分类及其可见分区 |
| GET | `/api/v1/tags` | 可用标签（非同义词、对该密钥可见） |
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

### 写入端点

写入端点要求密钥具备 `write` scope **且**绑定了用户（`user:`）——所有写操作都以该用户身份执行，
从而复用既有领域服务（`Community::CreateTopic` / `Community::CreatePost`）的权限、信任等级与防刷限制。
缺少 `write` scope 返回 `403 insufficient_scope`；有 scope 但未绑定用户返回 `403 write_requires_user`；
领域服务校验失败（如标题为空、发帖过快）返回 `422 unprocessable` 并在 `message` 给出原因。

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
