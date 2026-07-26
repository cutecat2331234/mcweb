# McWeb CE Developer Mode

> 状态：部分实现，可用于受控开发环境
> 最近复核：2026-07-26
> 版本范围：McWeb CE；EE 必须先合并 CE 的通用实现，再追加 EE 专属行为

Developer Mode 是启动期配置，不是管理员后台中的热开关。它可以关闭一批妨碍本地
调试的安全校验和生产优化，并将部分外部副作用替换为本地 fake/capture adapter。
它不会创建隔离数据库，也不会取消 RBAC、资源归属、数据库约束或金额状态机。

开启后，任何能够访问该实例的人都会面对被放宽的安全边界；配置了自动登录时，
访问者还可能直接获得指定开发账号的会话。只能在隔离的开发数据库和受控网络中使用。

## 1. 开启与关闭

`config/local.yml` 已被 `.gitignore` 和 `.dockerignore` 排除。以
`config/local.yml.example` 为模板，在本机配置中加入：

```yml
developer_mode:
  enabled: true
  preset: unrestricted
  security: {}
  integrations: {}
  runtime: {}
  auto_login_user:
```

当前只有 `unrestricted` preset。启用时，程序先加载该 preset，再用三个分组中的
显式值覆盖它；把单项设置为 `inherit` 可以恢复当前 Rails 环境原本的行为。例如：

```yml
developer_mode:
  enabled: true
  preset: unrestricted
  security:
    csrf: inherit
  runtime:
    job_backend: inline
```

不要为了方便盲目把外部集成设为 `inherit`。例如
`integrations.payments: inherit` 会重新允许已配置的真实支付 provider。

环境变量 `MCWEB_DEVELOPER_MODE` 的优先级高于 YAML 开关：

| 值 | 结果 |
|---|---|
| `1`、`true`、`yes`、`on` | 强制开启 |
| `0`、`false`、`no`、`off` | 强制关闭 |
| 其他值，包括已定义但为空 | 启动失败 |
| 未定义 | 使用 `config/local.yml` 的 `enabled` |

环境变量只覆盖总开关，不覆盖 preset 或细项。没有 `developer_mode` 配置段时默认关闭。
配置文件使用严格解析：无效 YAML、未知键、错误枚举、非布尔 `enabled` 或无效的
`auto_login_user` 都会在 Rails 初始化前中止启动。即使总开关为 `false`，错误的细项
仍会被校验，避免以后启用时静默采用错误配置。

在 `RAILS_ENV=production` 中开启还必须同时提供以下独立确认：

```text
MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION=I_ACCEPT_UNSAFE_DEVELOPER_MODE
```

确认值大小写敏感，必须逐字匹配；空值、`true`、`yes`、多余空格和其他近似值都会使
production 启动 fail-closed。该变量只是生产风险确认，不会单独开启模式；总开关仍是
`developer_mode.enabled` / `MCWEB_DEVELOPER_MODE`。Web、Worker、Rake 等每个
production 进程都必须收到相同确认值。

可选的 `MCWEB_LOCAL_CONFIG_PATH` 能把本地配置指向另一个未入库文件；不要把该文件、
实际账号、密钥或数据库凭证写进文档或提交。

覆盖值遵循固定 schema：

- 下文 security/integration 表中的每项只接受 `inherit` 或表内的 Developer Mode
  默认值。
- runtime 的布尔型选项接受 `inherit`、`enabled`、`disabled`。
- `job_backend` 接受 `inherit`、`async`、`inline`；`log_level` 接受
  `inherit`、`debug`、`info`、`warn`、`error`、`fatal`。
- `puma_workers` 必须是非负整数；关闭模式时不会应用该值。

## 2. `unrestricted` 当前实际行为

### 2.1 已接线的安全行为

| 配置项 | 默认值 | 当前实现 |
|---|---|---|
| `transport` | `http_allowed` | 在所有 Rails 环境中取消 `force_ssl`、`assume_ssl` 和 HSTS 配置。不会修改防火墙、代理或 Puma 监听地址。 |
| `host_authorization` | `bypass` | 清空 Rails Host allowlist。 |
| `csrf` | `bypass` | 关闭 Rails forgery protection。 |
| `frame_protection` | `disabled` | 删除全局 `X-Frame-Options`。附件下载等端点自己的 sandbox 响应头仍保留。 |
| `cors` | `allow_all` | 插入宽松 CORS middleware，处理预检并反射请求 Origin。 |
| `secure_cookies` | `disabled` | Session 与 XSRF Cookie 在 HTTP 下不要求 Secure；签名、HttpOnly 和 SameSite 仍保留。 |
| `email_verification` | `auto_verify` | 新注册用户直接标记已验证且不发送验证邮件，并单独记录 `developer_mode_email_verified` 来源；已有未验证用户可登录，但其数据库状态不会被批量修改。关闭该 bypass 后，开发模式自动验证的账号必须从“重新发送验证邮件”入口完成一次真实验证。 |
| `two_factor` | `bypass` | 登录和强制设置流程跳过 TOTP；密钥与恢复码不会删除。 |
| `password_policy` | `relaxed` | 取消 User 模型的最短 6 字符校验；密码哈希及其他账号校验仍执行。短密码会记录 `developer_mode_relaxed_password` 来源；关闭该 bypass 后不能再登录，完成一次符合正常策略的密码重置后自动解除标记。 |
| `rate_limits` | `bypass` | `Administration::RateLimiter` 返回 bypass 结果且不写计数器，调用它的 AbuseRateLimit 同样生效。 |
| `account_lockout` | `bypass` | 忽略现有锁定，不累计失败次数，也不清除原有锁定状态；密码仍必须正确，自动登录除外。 |
| `anti_spam` | `bypass` | 绕过邮箱/IP ban、板块信任门槛、PM/link/upload/reaction trust gate、自动审核阈值、发帖/主题间隔、重复内容、slow mode、bump cooldown 与签名最低信任等级。登录、RBAC/板块权限、用户 block、banned/silenced/mute、内容长度/标签/前缀、warning sanction 和内容状态机仍执行。 |
| `inbound_webhook_signatures` | `bypass` | 当前只在支付 `ReceiveWebhook` 中跳过 provider 签名验证，并记录安全的通知事件。事件标识、payload 规范化、幂等和 provider allowlist 仍执行。 |
| `outbound_url_safety` | `allow_http_private_networks` | `UrlSafety` 允许 HTTP、localhost 和私网目标；仍要求 HTTP(S) URI、主机、无 userinfo，并保留解析和超时边界。 |
| `attachment_malware_scan` | `assume_clean` | 不调用 ClamAV，返回 scanner=`developer_mode`、code=`dev_bypassed`，不会伪装成真实扫描器结果。该结果只在 Developer Mode 开启期间可绑定/下载；关闭后立即 fail-closed，并由附件扫描周期任务重新送入真实扫描器，真实扫描通过前不可下载。 |
| `attachment_quota` | `bypass` | 跳过站点、身份组和账号配额判定，但仍创建正常的 upload reservation，输入与数据库约束继续执行。 |
| `browser_policy` | `bypass` | 跳过 Rails modern-browser gate。 |

`csp: disabled` 已进入严格配置 schema，但 McWeb 当前没有全局 CSP 可供切换，因此该值
目前不会额外修改响应。附件与上传下载端点显式设置的
`Content-Security-Policy: sandbox` 永远保留。

`plugin_signature: allow_unsigned` 需要单独解释：当前 Marketplace 本来就没有可关闭的
密码学签名校验，所以 Developer Mode 没有、也不应伪造一个“签名已绕过”分支。
该配置值目前是兼容性 no-op。插件包仍必须提供匹配的 SHA-256，并通过 ZIP、路径、
大小、manifest 和加载边界；`plugin_marketplace: local_only` 只负责阻止远程来源。

### 2.2 已接线的集成替身

| 配置项 | 默认值 | 当前实现 |
|---|---|---|
| `mail` | `file_capture` | Action Mailer 使用 file delivery，写入 `tmp/developer-mode/mails`，不连接 SMTP。 |
| `outbound_webhooks` | `capture` | `UrlSafety.safe_http_post` 不发起网络请求，写入本地 JSONL 并返回模拟的 HTTP 202。 |
| `payments` | `fake` | Checkout 只暴露一个虚拟 fake provider；Stripe 即使已在数据库启用也不可选，fake 支付与退款走正常订单/金额状态机。Stripe 连接测试会在查询 provider 配置和读取密钥前返回 `developer_mode_fake_only`，对账同样被阻止；只有显式改为 `inherit` 并重启后才允许连接 Stripe。 |
| `web_push` | `capture` | 对仍可见、偏好允许且具有订阅的通知逐条写入本地 JSONL，不读取 VAPID 密钥，也不调用 Web Push 网络 adapter。 |
| `minecraft_nodes` | `simulate` | NodeTask 与旧 ConnectorTask 都在本地通过各自 dispatcher 标记完成，不唤醒节点，也不会把控制台命令、广播、履约或集成动作交给真实 Connector。控制台命令模拟不要求 Connector 在线；原有输入、节点/服务器归属和任务类型校验仍执行。Connector 轮询只会收到空任务列表，并会先在本地收口最多 10 条旧 pending 任务。 |
| `remote_skin_lookup` | `simulate` | `RefreshSkin` 只读取现有 active PlayerIdentity 和已保存皮肤字段并返回 `simulated: true`，不请求 Mojang。 |
| `plugin_marketplace` | `local_only` | Marketplace package source 只接受 `file:`，拒绝 HTTPS 来源；本地包仍执行来源、SHA-256、ZIP 大小、路径穿越和解压边界校验。 |
| `object_storage` | `local` | Active Storage 切换到 `local` service。 |

### 2.3 已接线的运行时覆盖

`unrestricted` 默认应用以下启动期设置：

| 配置项 | 默认值 | 当前效果 |
|---|---|---|
| `class_reloading` | `enabled` | `config.enable_reloading = true` |
| `eager_load` | `disabled` | `config.eager_load = false` |
| `full_error_reports` | `enabled` | 所有请求按本地请求显示完整错误 |
| `controller_caching` | `disabled` | 关闭 controller caching |
| `fragment_caching` | `disabled` | 使用 `null_store` |
| `asset_cache` / `static_asset_far_future_headers` | `disabled` | Rails 静态文件使用 `Cache-Control: no-store` |
| `asset_minification` | `disabled` | Vite build 关闭 minify |
| `source_maps` | `enabled` | Vite build 生成 source map |
| `response_compression` | `disabled` | 如果应用加载了 `Rack::Deflater`，将其移除；反向代理压缩不受影响 |
| `job_backend` | `async` | Active Job 使用进程内 async adapter；可显式改为 `inline` |
| `puma_workers` | `0` | Puma 不启用 worker 集群 |
| `log_level` | `debug` | Rails 使用 debug 日志 |
| `verbose_query_logs` | `enabled` | 启用查询来源、query tags、Job enqueue 和 redirect 详细日志 |
| `server_timing` | `enabled` | 启用 Server-Timing |
| `template_annotations` | `enabled` | 渲染结果增加模板文件注释 |

Vite 两个设置只影响构建配置；Developer Mode 不会自动启动 Vite dev server，也不会
自动提供 HMR。`async` Job 在进程退出时可能丢失，`local` storage 也不是持久生产存储。

此外，Sidekiq server 在 Developer Mode 下会禁用 Cron poller，也不会调用
`Sidekiq::Cron::Job.load_from_hash!` 自动注册 `config/sidekiq_cron.yml`。切换前已经
存在于 Redis 的 Cron 记录会保留，但不会被自动入队；手动执行与 Sidekiq dashboard
仍可使用。后台任务页以及 `/health/live`、`/health/ready` 会暴露
`scheduled_jobs_auto_registration: false`。项目当前没有 Prometheus metrics
endpoint，因此没有另行虚构或导出同名 gauge。

### 2.4 可见性

开启后目前可见的标志有：

- 官网、`/app`、`/admin` 和旧 Rails 页面持续显示 Developer Mode 警告横幅。
- production 环境中的横幅追加红色生产警告，启动日志输出 CRITICAL/FATAL 警告。
- HTML `<title>` 带 `[DEV]` 前缀，页面带 `data-developer-mode="true"`。
- HTML meta 与动态响应均标记 `noindex, nofollow`。
- 动态响应带 `X-McWeb-Developer-Mode: unrestricted` 和
  `Cache-Control: no-store`。
- `/health/live` 与 `/health/ready` JSON 带 mode、profile 和周期任务自动注册状态。
- 管理后台“后台任务”页显示 mode/profile 与 Cron 自动注册状态。
- 具备 `system.settings.manage` 的管理员可访问
  `/admin/system/developer-workbench`，查看最终生效配置与安全脱敏的本地状态。

`noindex` 只是搜索引擎提示，不是访问控制。

### 2.5 Developer Workbench

Workbench 是只读诊断页，不是 Developer Mode 配置页：

- Developer Mode 关闭时，路由在认证处理前直接返回 `404`，侧栏入口也不出现。
- 开启时仍要求普通后台访问条件、`admin.access` 和
  `system.settings.manage`；Developer Mode 不绕过这些 RBAC 检查。
- 页面显示 profile、production 风险、security/integrations/runtime 最终生效枚举、
  Cron 自动注册状态，以及 `auto_login_user` 是否已配置；自动登录目标值绝不返回。
- 邮件、Webhook、Web Push 只显示相对目录、有限文件统计和最新白名单元数据。
  服务端不会把邮件正文、URL、headers、payload、完整 capture ID 或绝对路径放入
  Inertia props。
- Minecraft 区域只汇总 Developer Mode 模拟任务的类型、状态与时间，不返回节点、
  服务器、任务 payload 或 result。
- “系统设置”和“后台任务”按钮使用 Inertia 内部导航；页面没有启用、关闭、清理或
  重放操作。模式开关仍只能修改 `config/local.yml` 或启动环境变量并重启进程。

## 3. production 环境仍强制保留的 foundation

Developer Mode 可以在 `RAILS_ENV=production` 下显式开启，但必须同时提供
`MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION=I_ACCEPT_UNSAFE_DEVELOPER_MODE`；
缺失或不精确时启动立即失败。通过双重确认后，仍不会跳过以下启动基础：

- `SECRET_KEY_BASE` 必须存在、不是占位值且至少 64 字节。
- `LOCKBOX_MASTER_KEY` 必须存在、不是占位值且为 64 个十六进制字符。
- 应用仍使用真实 PostgreSQL adapter。提供 `DATABASE_URL` 时必须是带数据库名的
  PostgreSQL URL；使用 `MCWEB_DATABASE_HOST` 时仍要求用户名和密码，且占位密码会被拒绝。

默认 `unrestricted` 可免除与已替换能力直接相关的生产配置：HTTPS public origin、
Host allowlist、trusted proxy、SMTP、Action Mailbox relay secret 和 S3。若把相应项
改回 `inherit`，production 校验会按粒度恢复：

| 恢复的配置 | 重新要求 |
|---|---|
| `security.transport: inherit` | HTTPS public origin 与 trusted proxy policy |
| `security.host_authorization: inherit` | public origin 与 exact host allowlist |
| `integrations.mail: inherit` | public origin、SMTP、发件地址与 inbound mail secret |
| `integrations.object_storage: inherit` | private S3-compatible storage 配置 |

Developer Mode 也没有通用的权限后门。以下正常代码路径继续运行：

- 密码认证（显式自动登录除外）、用户未删除/未封禁检查和 Session 创建。
- RBAC、身份组、后台权限、版主权限、资源所有权和私密内容可见性。
- Strong Parameters、HTML 清理、SQL 参数化、文件路径及下载授权。
- 数据库唯一约束、事务、幂等、库存、余额、礼品卡、订单、退款和权益状态机。
- 捕获内容的参数过滤以及应用日志的敏感参数过滤。

production Puma 仍默认绑定 `127.0.0.1`，除非部署配置显式设置现有的监听参数。
Developer Mode 取消的是应用层 Host/协议/CORS 限制，不会开放端口、防火墙或代理。

## 4. 自动登录

`auto_login_user` 可使用一个正整数 User ID，或不超过 255 字符的用户名、邮箱、
public ID。留空表示不自动登录：

```yml
developer_mode:
  enabled: true
  preset: unrestricted
  auto_login_user: dev-owner
```

行为边界：

- 只在没有现有 Session 的 GET HTML 请求上尝试；JSON、API 和其他非 HTML 请求不生效。
- 用户不存在、已删除、已封禁或无法创建 Session 时静默跳过。
- 创建的是普通真实 Session，不会提升账号权限；普通会员访问后台仍会被拒绝。
- 已有 Session 不会被替换。测试另一个账号时应先退出或使用新的无痕窗口。
- Developer Mode 下签发的全部 Session 都带来源标记；关闭模式后这些 Session
  立即不再属于 active scope，下一次携带它们的请求会撤销记录并删除 Cookie。

自动登录不要求密码，因此不要在共享或公网可达实例中配置高权限账号。

## 5. 本地捕获与 fake 支付

路径均相对于 Rails 项目根目录：

| 类型 | 路径 | 内容与边界 |
|---|---|---|
| 邮件 | `tmp/developer-mode/mails/` | Action Mailer 生成的本地邮件文件。邮件正文可能包含验证链接、重置链接或用户内容。 |
| 出站 Webhook | `tmp/developer-mode/webhooks/YYYY-MM-DD.jsonl` | 按 UTC 日期追加；URL 的 userinfo 与完整 path 会移除（避免泄漏 Discord/Slack 等 path token），query、headers 和 JSON payload 按敏感参数过滤。非 JSON body 只保存字节数与 SHA-256。文件权限为 `0600`。 |
| Web Push | `tmp/developer-mode/web-push/YYYY-MM-DD.jsonl` | 按 UTC 日期追加；endpoint 只保存 SHA-256，payload 再经过敏感字段过滤。文件权限为 `0600`。 |

这些目录由 `tmp/` 忽略规则排除，不应复制到 issue、聊天、构建产物或生产备份。过滤器
只能覆盖已知敏感字段，业务正文仍可能包含隐私数据。

Web Push 只有在通知仍对用户可见、用户偏好允许且至少存在一个 PushSubscription 时才
会产生捕获记录。撤销内容访问后不会为了调试而绕过可见性。

fake 支付没有独立捕获目录。它创建正常的 payment/order 数据并使用
`/app/payments/fake/...` 完成支付，退款也走正常服务层。因此必须使用可丢弃的开发
数据库；“fake”只代表不连接外部支付网络，不代表不会修改业务数据。

## 6. 启动后验证

### 6.1 检查最终开关

启动同一环境下执行：

```sh
bin/rails runner 'settings = Mcweb::DeveloperMode.settings; puts({ enabled: settings.enabled?, profile: settings.profile, auto_login_configured: settings.auto_login_user.present? }.inspect)'
```

只输出是否启用、profile 和是否配置自动登录，不输出账号或其他本地配置。

### 6.2 检查 HTTP 标志

启动 Web 服务后：

```sh
curl -i http://127.0.0.1:3000/health/live
curl -i http://127.0.0.1:3000/health/ready
```

预期至少看到：

- `X-McWeb-Developer-Mode: unrestricted`
- `X-Robots-Tag: noindex, nofollow`
- `Cache-Control: no-store`
- health JSON 中的 `"developer_mode": true`、
  `"developer_mode_profile": "unrestricted"` 和
  `"scheduled_jobs_auto_registration": false`

readiness 仍会检查真实依赖，依赖故障时可以返回 `503`；这不表示 Developer Mode
未生效。

再分别打开官网、`/app` 和 `/admin`，确认警告横幅与 `[DEV]` 标题存在。若配置了
自动登录，用无痕窗口发起一次 GET HTML 请求，并确认最终权限与配置用户自身一致。

### 6.3 检查替身

- 触发一封邮件后检查 `tmp/developer-mode/mails/`，确认未连接 SMTP。
- 触发一个使用 `UrlSafety.safe_http_post` 的 Webhook 后检查当天的 JSONL，并确认
  目标服务没有收到请求。
- 为测试用户保留有效 PushSubscription 和通知偏好，触发通知后检查
  `tmp/developer-mode/web-push/`。
- 打开结算页，确认 provider 只有 fake；完成一次测试订单后核对订单、payment 和
  权益状态，不要只检查页面提示。
- 创建一个 Minecraft node task，确认任务本地完成并带 `simulated` 标志；刷新已有
  玩家皮肤时确认不会请求 Mojang。
- 为 Marketplace 选择一个本地 `file:` package，确认 HTTPS 来源被拒绝，同时
  SHA-256 与 ZIP 校验仍执行。
- 上传附件后核对扫描记录显示 `developer_mode` / `dev_bypassed`，而不是 ClamAV
  clean。

PowerShell 可用以下只读命令查看捕获文件：

```powershell
Get-ChildItem -LiteralPath 'tmp/developer-mode' -Recurse -File
```

## 7. 修改配置后的重启要求

`Mcweb::DeveloperMode.settings` 在 `config/boot.rb` 中读取并缓存。修改
`config/local.yml`、`MCWEB_DEVELOPER_MODE` 或任何细项后，必须重启：

- Rails/Puma Web 进程。
- 独立 Job/Sidekiq 进程。
- Vite dev server；涉及 minify/source map 时还要重新 build。

`puma_workers`、Rails middleware、CSRF/Host/CORS、cache store、Active Job adapter、
Action Mailer、Active Storage 和 Vite build 选项都不能靠刷新浏览器生效。当前没有
后台热切换，也没有配置自动重载。

## 8. 风险警告

- 不要在生产数据、共享数据库或公网实例上使用；production 的精确双重确认只用于
  明确、可测试的应急开发场景，不代表安全，也不能由部署模板默认填入启用值。
- 开启后 CSRF、Host、CORS、TLS 强制、Secure Cookie、TOTP、限流等多层防护会同时
  变弱，任何可达访问者都可能利用它们。
- `auto_login_user` 可能直接暴露指定账号会话，尤其不得指向真实 owner/admin。
- fake 支付、自动登录、上传和 Job 仍会写当前数据库；fake 资金状态不会因关闭模式
  自动回滚，因此必须使用隔离的开发数据库。
- 开发模式自动验证邮箱或接受短密码时会记录来源；关闭对应 bypass 后账号必须完成
  真实邮箱验证、强密码重置，开发模式 Session 也会自动失效。
- `async` Job 与本地存储不耐进程退出；不要把它们当作持久队列或备份。
- 本地邮件和捕获 JSONL 仍可能包含用户内容，不得提交或公开。
- `noindex`、横幅和响应头只是警告与可观察性，不是安全控制。
- 关闭前应删除总开关与 production 确认变量并重启全部进程，再重新核验 headers、
  provider 和邮件 adapter，不能只把 YAML 改回 `false`。

## 9. 当前未实现

以下仍属于活动计划，不能从配置名称或 UI 文案推断为已完成：

- 捕获记录浏览/清空 UI、前端调试抽屉和可下载的脱敏诊断包。
- owner/moderator/member 一键身份切换；当前只有一个可选 `auto_login_user`。
- fake 支付的失败、取消、延迟到账等可选故障场景。
- 插件包密码学签名能力本身尚不存在；`plugin_signature: allow_unsigned` 当前是
  no-op，且绝不关闭 SHA-256/ZIP/路径/manifest 边界。
- 全局 CSP 切换；当前只确认没有全局 CSP，并保留端点 sandbox。
- 上传 clean/infected/quarantined/timeout 一键场景制造工具。
- 模式开关与配置变化的持久审计日志、`mcweb_developer_mode` 指标和完整系统信息面板。
- 独立视觉水印；当前已有横幅、`[DEV]` 标题、HTML 属性和响应头。
- 自动启动 Vite HMR、完整多网络浏览器 E2E，以及每个声明 capability 的成对门禁。

进度与未完成验收项以
[`code-completion-and-developer-mode-plan.md`](code-completion-and-developer-mode-plan.md)
为准。

## 10. 实现与测试入口

主要实现：

- `lib/mcweb/developer_mode.rb`
- `config/developer_mode_runtime.rb`
- `lib/mcweb/developer_mode_capture.rb`
- `app/controllers/concerns/authentication.rb`
- `app/services/payments/provider.rb`
- `app/services/community/deliver_web_push.rb`
- `app/services/minecraft/enqueue_node_task.rb`
- `app/services/minecraft/refresh_skin.rb`
- `lib/mcweb/plugins/marketplace/package_source.rb`
- `lib/mcweb/sidekiq_cron_schedule.rb`

主要回归测试：

- `test/lib/mcweb/developer_mode_test.rb`
- `test/lib/mcweb/developer_mode_runtime_test.rb`
- `test/lib/mcweb/developer_mode_capture_test.rb`
- `test/integration/developer_mode_auto_login_test.rb`
- `test/integration/developer_mode_visibility_test.rb`
- `test/services/developer_mode_identity_test.rb`
- `test/services/community/developer_mode_attachment_guards_test.rb`
- `test/services/community/deliver_web_push_developer_mode_test.rb`
- `test/services/payments/developer_mode_isolation_test.rb`
- `test/services/minecraft/developer_mode_integrations_test.rb`
- `test/lib/mcweb/plugins/marketplace/developer_mode_source_test.rb`
