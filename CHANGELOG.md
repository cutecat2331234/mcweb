# CHANGELOG

## Unreleased

### Fixed

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

