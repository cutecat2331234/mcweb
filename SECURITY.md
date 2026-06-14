# 安全说明

## 报告漏洞

请通过站点管理员邮箱私下报告安全问题，不要在公开 Issue 中披露可利用细节。

## 密钥与凭据

- 支付密钥、Connector 密钥、SMTP 密码等使用 Lockbox 加密或受保护的环境配置存储
- 禁止将密钥提交到 Git 仓库
- 日志中不得输出密码、Session Token、TOTP Secret、支付密钥

## 认证与会话

- 密码使用 bcrypt 哈希
- 会话 Token 仅保存摘要，支持撤销与过期
- 登录、注册与验证码请求有限流
- 支持 TOTP 二步验证（可选强制管理员启用）

## Web 安全

- CSRF 保护（`protect_from_forgery`）
- CSP 与安全 Cookie（HttpOnly、SameSite、生产环境 Secure）
- 用户内容与 `CustomSafeHtml` 经白名单清理（Sanitize）
- 上传文件类型与大小限制

## 支付与发货

- 支付回调验证签名并幂等处理
- 发货使用全局唯一 `delivery_id`，Rails 与 Connector 双侧幂等

## 依赖审计

发布前请运行：

```bash
bundle exec bundler-audit check --update
bundle exec brakeman -q
```
