# CHANGELOG

## Unreleased

### Fixed

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

