# CHANGELOG

## Unreleased

### Fixed

- Minecraft 后台服务器列表/详情改用 `address` 字段，修复 `NoMethodError: host`
- 注册与密码重置通过 `Identity::Mailer` 发送邮件
- 补充 `config/templates/install.env.example`
- `bin/setup` 在开发/测试环境保留 test gem，并自动 `npm ci`
- `bin/install` 支持 `--unattended`、安装 Node.js 并自动运行 setup

