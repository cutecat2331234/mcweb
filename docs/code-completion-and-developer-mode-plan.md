# McWeb CE 未完成代码与 Developer Mode 开发计划

> 状态：持续开发；P0 仓库代码基础已大幅闭环，真实环境验收、诊断与完整 E2E 尚未完成
> 最近复核：2026-07-28
> 优先级：Developer Mode 与 C0/C1/C2 为 P0，其余按依赖关系推进
> 范围：规划尚未实现、仅部分实现或尚未形成可靠闭环的代码；已落地基线只用于界定剩余工作
> 不包含：证书申请、域名解析、服务器采购、人工备份值班等纯运维事项

## 1. 版本边界与实施顺序

- CE 是所有通用能力的唯一上游。
- 通用代码必须先在 CE 实现、测试并进入 CE `main`，再由 EE 合并该提交历史。
- CE 保持现有用户前台风格，不按 EE 用户前台重写。
- CE 不包含 Action Cable、WebSocket、Discord 类频道或其他 EE 实时运行时代码。
- EE 专属实时与频道计划见 EE 仓库的
  `docs/ee-code-completion-and-developer-mode-plan.md`。
- 已通过验收的功能不重复开发；进度表中的已落地基线只用于防止重复实现。

## 2. 总体交付顺序

1. 完成 Developer Mode 剩余诊断、模拟 adapter 和测试门禁；统一基础设施已经落地。
2. 完成附件安全、配额和生命周期闭环。
3. 完成真实支付、Webhook、退款和对账闭环。
4. 完成公网滥用防护、查询规模和权限回归矩阵。
5. 完成审核、数据生命周期和商城运营后台。
6. 完成 I18N、可访问性、E2E、故障注入及可观测代码。
7. CE 形成候选提交后，再由 EE 合并并实施 EE 专属阶段。

各阶段必须独立可测试、可回滚；不得把所有工作压在一个超大提交中。

## 3. Developer Mode

当前运行行为以 [`DEVELOPER_MODE.md`](DEVELOPER_MODE.md) 为准。下方 3.1 至 3.6
同时保留目标设计和安全边界，不能因为某个配置键已进入 schema 就把对应 adapter
视为完成。

### 3.0 当前进度摘要

| 阶段 | 当前状态 | 已落地基线 | 主要剩余工作 |
|---|---|---|---|
| D1 策略与配置 | 基本完成 | 启动期严格解析、`unrestricted` preset、环境变量覆盖、枚举覆盖、production 精确双重确认与分粒度校验、Workbench 脱敏最终配置摘要 | 更完整的运维输出 |
| D2 身份与请求安全 | 部分完成 | 邮箱验证/TOTP/锁定/密码/限流与反垃圾绕过；CSRF、TLS、Host、CORS、Cookie、Frame、浏览器策略；可选单账号自动登录 | 多身份切换；CSP 的明确全局策略；逐 capability 成对门禁 |
| D3 外部服务替身 | 部分完成 | 邮件文件捕获、出站 Webhook JSONL、Web Push JSONL、Workbench 安全捕获摘要、fake-only 支付、Minecraft task/远程皮肤模拟、Marketplace local-only、本地 Active Storage | 完整捕获浏览与清理 UI；fake 失败/取消/延迟场景；插件签名能力本身尚不存在 |
| D4 上传与任务 | 部分完成 | 扫描 `dev_bypassed`、上传配额绕过、async/inline Job 选择、Sidekiq Cron poller 与启动注册抑制、旧 Redis 记录停止自动入队 | 上传状态故障注入；更完整手动触发机制 |
| D5 可见性与诊断 | 部分完成 | 三套前端与旧页面横幅、`[DEV]` 标题、noindex、响应头、live/readiness 标志、production CRITICAL 警告、RBAC Workbench | 调试抽屉、水印、诊断包、配置变化审计、场景 seed；若引入指标端点再增加 gauge |
| D6 测试门禁 | 部分完成 | parser/runtime、production boot、身份、自动登录、附件、支付隔离、Webhook/Web Push 捕获、Workbench 404/RBAC/脱敏和可见性测试 | 完整 capability 矩阵、多网络浏览器 E2E、真实外部服务零调用的全链路证明 |

Developer Mode 目前不是完整交付状态。`plugin_signature` 只有配置声明，原因不是
绕过尚未接线，而是项目当前没有密码学插件签名能力可关闭；SHA-256、ZIP、路径、
manifest 和加载边界仍必须保留。实际运行边界详见 `DEVELOPER_MODE.md`。

### 3.1 目标

Developer Mode 是由配置开关控制的开发运行模式，用于避免以下事项反复阻塞开发：

- HTTPS、HSTS、安全 Cookie、Host 和 Origin 限制。
- 邮箱验证、强制 TOTP、登录锁定和公网限流。
- CSRF、CSP、浏览器版本、密码强度和其他安全验证。
- 真实 SMTP、真实支付、真实 Webhook、Web Push 和 Minecraft 外部副作用。
- 上传病毒扫描、隔离等待和后台 Worker 依赖。
- 缓存、压缩、预编译、延迟加载等不利于调试的生产优化。
- 多账号、固定数据和重复测试数据的准备成本。

Developer Mode 默认关闭，主开关位于配置中。开启后允许通过 localhost、局域网、
公网 IP、域名、反向代理、HTTP 或 HTTPS 等任意正常访问方式使用，不增加来源 IP、
CIDR、一次性令牌或 loopback 限制。

### 3.2 统一入口

新增 `Mcweb::DeveloperMode`，所有开发绕过都必须通过该对象判断，禁止继续在业务
代码中增加零散的 `Rails.env.development?` 分支。

建议接口：

```ruby
Mcweb::DeveloperMode.enabled?
Mcweb::DeveloperMode.profile
Mcweb::DeveloperMode.allow?(:skip_email_verification)
Mcweb::DeveloperMode.optimization?(:eager_load)
Mcweb::DeveloperMode.block_external_side_effects?
Mcweb::DeveloperMode.settings
```

主配置写入不进入 Git 的 `config/local.yml`：

```yml
developer_mode:
  enabled: false
  preset: unrestricted

  security:
    transport: http_allowed
    host_authorization: bypass
    csrf: bypass
    csp: disabled
    frame_protection: disabled
    cors: allow_all
    secure_cookies: disabled
    email_verification: auto_verify
    two_factor: bypass
    password_policy: relaxed
    rate_limits: bypass
    account_lockout: bypass
    anti_spam: bypass
    inbound_webhook_signatures: bypass
    outbound_url_safety: allow_http_private_networks
    attachment_malware_scan: assume_clean
    attachment_quota: bypass
    plugin_signature: allow_unsigned
    browser_policy: bypass

  integrations:
    mail: file_capture
    outbound_webhooks: capture
    payments: fake
    web_push: capture
    minecraft_nodes: simulate
    remote_skin_lookup: simulate
    plugin_marketplace: local_only
    object_storage: local

  runtime:
    class_reloading: enabled
    eager_load: disabled
    full_error_reports: enabled
    controller_caching: disabled
    fragment_caching: disabled
    asset_cache: disabled
    asset_minification: disabled
    response_compression: disabled
    source_maps: enabled
    static_asset_far_future_headers: disabled
    job_backend: async
    puma_workers: 0
    log_level: debug
    verbose_query_logs: enabled
    server_timing: enabled
    template_annotations: enabled

  auto_login_user:
```

`enabled` 是唯一总开关。`false` 时忽略其余 Developer Mode 配置并完整使用正常
环境配置；`true` 时先加载 `unrestricted` preset，再用下方细项覆盖。也可以提供
`MCWEB_DEVELOPER_MODE=1` 作为启动脚本或容器环境变量覆盖，但最终状态必须统一由
`Mcweb::DeveloperMode` 读取。

配置在启动期读取，修改后需要重启。第一阶段不把开关写入数据库，避免数据库复制、
seed 或 SiteSetting 使环境行为发生不可见漂移；后续若需要后台切换，必须单独设计。
安全、集成和运行时配置使用枚举，不使用含义相反的多层布尔值。未知键、拼写错误、
未知枚举值必须启动失败；这是配置正确性检查，不是访问限制。

### 3.3 激活与访问语义

- Developer Mode 是否启用只取决于配置开关，不根据请求来源、Host、协议或
  `remote_ip` 再次拦截。
- 不检查 `Rails.env`、监听地址、Host、Remote IP、CIDR 或反向代理来源；允许
  localhost、局域网、公网 IP、域名、HTTP、HTTPS 和反向代理等任意正常访问方式。
- 开启后所有路由沿用原本的访问入口，不建立 `/dev-only` 网络边界。
- Rails 以 production 环境启动时，配置开关与独立的大小写敏感固定确认短语必须
  同时存在；缺少确认或使用 `true` 等近似值时 fail-closed。确认通过后才关闭下面
  列出的生产优化。
- 启动日志、页面横幅、响应头、健康接口和 HTML meta 必须明确显示 Developer Mode。
- 开启时默认使用 fake/capture/recording adapter，避免真实外部副作用；需要连接
  测试沙箱时按单项配置启用。
- 开启时设置 `noindex, nofollow`，但不阻止网络访问。

确认启用后允许任意网络访问是有意设计。系统不增加 loopback、CIDR 或 Host
限制，但 production 必须通过独立精确确认以防单个总开关误配置；将已确认开启的
实例暴露到公网所产生的风险仍由部署者承担。

禁止以下隐式开启方式：

- 根据域名、IP、debug 参数、Cookie 或用户角色自动开启。
- 因为配置解析失败而默认开启。
- 在单个控制器中自行判断 `Rails.env` 后绕过，而不经过统一策略对象。

### 3.4 默认关闭的安全验证

| 验证或限制 | Developer Mode 行为 | 仍保留 |
|---|---|---|
| 邮箱验证 | 新注册账号直接验证，已有未验证账号允许登录 | 原始验证状态不被批量破坏 |
| TOTP | 跳过登录和强制设置步骤 | 不删除 TOTP 密钥和恢复码 |
| 登录锁定 | 不累计失败次数、不写锁定时间 | 密码仍需正确，除非使用显式身份切换 |
| 密码强度 | 允许短开发密码 | 密码哈希和唯一账号规则 |
| IP/邮箱封禁 | 可跳过封禁和黑名单检查 | 用户删除状态和数据归属 |
| 业务限流 | 返回无限额度且不写计数器 | 原调用点和响应结构 |
| CSRF | 全局关闭 forgery protection | 参数过滤和服务层鉴权 |
| CSP/Frame 防护 | 不发送 CSP 和 X-Frame-Options，允许 HMR、inline、eval 和嵌入调试 | 输出转义与内容清理 |
| HTTPS/HSTS | 不强制跳转，不发送 HSTS | 会话仍保持签名和 HttpOnly |
| Secure Cookie | 允许 HTTP 下发送开发 Cookie | Cookie 签名和独立 CE/EE 名称 |
| Host/Origin/CORS | 不限制 Host、Origin 或访问来源 | 路由和身份鉴权 |
| 浏览器版本 | 不执行现代浏览器拦截 | 页面能力检测和降级提示 |
| 反垃圾/冷却/信任门槛 | 跳过板块/PM/link/upload/reaction trust gate、自动审核阈值、发帖与主题间隔、重复内容、slow mode、bump cooldown 和签名最低信任等级 | 登录、RBAC/板块权限、用户 block、banned/silenced/mute、内容结构校验、warning sanction、人工审核接口和内容状态机 |
| Webhook 签名 | capture/fake 入站工具可跳过 | 真实 provider adapter 的独立测试 |
| 出站 URL 安全 | 允许 HTTP、localhost 和私网测试 endpoint | URL 解析、超时和响应大小上限 |
| 上传扫描 | 直接标记 `dev_bypassed` | 文件名、路径、单文件大小和解码资源上限 |
| 上传配额 | 关闭用户、身份组和站点配额 | 单请求体大小上限 |
| 插件签名/来源 | 可加载明确的本地开发插件 | manifest 解析、路径和加载异常隔离 |

Developer Mode 同时允许本地或私网 HTTP endpoint，用于调试 Webhook、Minecraft
节点、皮肤和其他集成；真实 adapter 仍必须逐项显式选择，不能因为 Developer Mode
开启而意外出网。

### 3.5 默认关闭的生产优化

Developer Mode 必须在 Rails 初始化早期生效，因为以下选项不能在请求中途可靠切换：

| 生产优化 | Developer Mode 行为 |
|---|---|
| eager load / class cache | 关闭 eager load，启用代码重载 |
| controller/fragment/data cache | 使用 null/memory store，默认不缓存页面和片段 |
| HTTP cache | 响应使用 `no-store`，静态资源不设置长期 immutable |
| Vite/前端资产 | 使用开发服务器、HMR、source map，不依赖预编译产物 |
| JS/CSS minify | 关闭压缩和混淆，保留可读堆栈 |
| 响应压缩 | 可关闭 gzip/brotli，方便检查原始响应 |
| 数据库日志 | 开启 verbose query log、SQL 标签和慢查询提示 |
| 错误页面 | 显示完整异常、调用栈和 request id |
| 后台任务 | 使用 async 或 inline，不要求 Redis/Sidekiq |
| 邮件 | capture 到本地邮箱并保留模板预览 |
| 存储 | 可使用本地 storage，并展示 Blob/附件调试信息 |
| 定时任务 | 默认不自动注册，提供手动触发入口 |
| CDN/预加载 | 关闭 CDN URL、预加载和长缓存 |
| EE Cable | EE 可切换 async Cable、inline fanout 和实时调试面板 |

此外增加开发工具栏，显示当前请求耗时、SQL 数量、缓存命中、Job、邮件、Webhook、
支付、上传和 EE WebSocket 事件摘要。

默认替代关系：

- 邮件写入 `tmp/developer-mode/mails`，不连接 SMTP。
- 出站 Webhook 保存请求并模拟成功，不实际发送。
- 支付固定使用 fake provider，不读取 live 凭证。
- Minecraft 节点、远程皮肤和市场查询使用可配置 fixture/recording adapter。
- Active Storage 使用本地磁盘；Job 使用进程内 async 或显式 inline。
- Puma 使用单进程，不启用生产 worker 集群或应用预加载。

### 3.6 永远不能关闭的边界

即使 Developer Mode 开启，以下规则仍必须执行：

- RBAC、身份组、资源所有权和私密内容可见性。
- 管理员、版主、普通用户和匿名用户的权限隔离。
- SQL 参数化、Strong Parameters、HTML 清理和输出转义。
- 文件路径、ZIP、模板、插件包和下载授权校验。
- 数据库唯一约束、事务、幂等键和金额守恒。
- 订单、余额、礼品卡、库存和权益的状态机。
- 敏感参数过滤，不得在日志或前端回显密码、令牌和密钥。
- 对真实外部系统的默认阻断。

这些边界如果被关闭，开发环境将无法发现越权、重复扣款和数据损坏问题。

### 3.7 Developer Mode 代码落点

#### D1：策略与配置（基本完成，保留缺口）

- [x] 新增 `lib/mcweb/developer_mode.rb`，并在 `config/boot.rb` 早期严格解析。
- [x] 定义固定 capability、preset 和枚举；未知键和值启动失败。
- [x] 支持 `MCWEB_DEVELOPER_MODE` 严格覆盖和测试依赖注入；测试默认关闭。
- [x] production 要求独立精确确认短语，并按 `inherit` 粒度恢复 public origin、
  Host、proxy、邮件和存储校验，同时永远保留应用密钥与数据库 foundation。
- [x] Workbench 输出脱敏的最终生效配置摘要；production 仍保留显著风险告警。

#### D2：身份与请求安全（部分完成）

- [x] 注册自动验证并跳过验证邮件；登录跳过验证状态、TOTP 和锁定，但保留密码、
  封禁、删除状态与 Session 规则。
- [x] 密码长度放宽、RateLimiter 无写入 bypass、邮箱/IP ban bypass。
- [x] 接入 CSRF、TLS/HSTS、Host、CORS、Secure Cookie、Frame 和浏览器策略。
- [x] 提供一个显式配置用户的 GET HTML 自动登录，不提升原账号权限。
- [x] 所有 Developer Mode 下签发的 Session 标记来源；关闭模式后 active scope
  立即排除，并在下一次请求撤销记录与清理 Cookie。
- [x] 标记开发模式自动验证邮箱和短密码来源；关闭对应 bypass 后要求真实邮箱验证
  与符合正常策略的密码重置，避免宽松凭据永久泄漏到正常模式。
- [x] anti-spam 绕过信任门槛、自动审核阈值、发帖/主题间隔、重复内容、
  slow mode、bump cooldown 与签名最低信任等级，同时保留登录、RBAC/板块权限、
  block/ban/silence/mute、内容结构校验、warning sanction 和状态机。
- [ ] 提供 owner/moderator/member 一键身份切换。
- [ ] 明确接线全局 CSP policy；当前无全局 CSP，端点 sandbox 始终保留。

#### D3：外部服务替身（部分完成）

- [x] 邮件写本地文件；出站 Webhook 与 Web Push 写脱敏 JSONL。
- [x] 支付强制使用虚拟 fake provider，真实 Stripe 不可选；连接测试在读取密钥前
  fail-closed，对账同样被阻止，基本 fake 支付与退款可走通。
- [x] Web Push capture 仍执行通知可见性、偏好和订阅校验，不读取 VAPID 密钥。
- [x] Minecraft node task 本地完成、远程皮肤读取现有数据且不请求 Mojang。
- [x] 旧 ConnectorTask 与新 NodeTask 都只在本地模拟完成，Connector 轮询永远
  不会取得待执行命令。
- [x] Marketplace 在 Developer Mode 下只接受本地 `file:` 包。
- [x] Workbench 提供邮件/Webhook/Web Push 的有限统计与最新白名单元数据，不读取正文。
- [ ] 提供完整捕获浏览与显式清理页面。
- [ ] 提供 fake 支付失败、取消、延迟到账等场景。
- [ ] 若产品需要密码学插件签名，先设计并实现该能力；当前
  `plugin_signature: allow_unsigned` 是 no-op，不得关闭现有 SHA-256/ZIP/路径边界。
- [ ] 为全部声明的集成证明 Developer Mode 不会静默调用真实外部服务。

#### D4：上传与任务（部分完成）

- [x] 扫描绕过返回独立的 `developer_mode` / `dev_bypassed` 状态。
- [x] 关闭 Developer Mode 后，绕过扫描的附件立即 fail-closed，并重新进入真实
  扫描周期；真实 clean 结果出现前不可绑定或下载。
- [x] 配额 bypass 保留 upload reservation 与正常数据约束。
- [x] 支持 `async` 和 `inline` Job adapter。
- [x] Worker 启动时禁用 Sidekiq Cron poller 且不加载 schedule；切换前的 Redis
  Cron 记录保留但不会自动入队，并在 live/ready health 与 admin jobs 显示状态。
- [ ] 提供一键制造 clean、infected、quarantined、timeout 文件状态。
- [ ] 补齐可审计的手动触发入口。

#### D5：可见性与诊断（部分完成）

- [x] 官网、Portal、Arco Admin 和旧 Rails 页面显示持续横幅。
- [x] `<title>` 增加 `[DEV]`，HTML/meta/响应头提供 noindex 和模式标志。
- [x] `/health/live` 与 `/health/ready` 返回 mode/profile/Cron 自动注册状态；
  production 启动与页面升级风险告警。
- [x] 普通启动命令读取配置，启动期配置变化明确要求重启。
- [x] 增加严格 RBAC 的只读 Developer Workbench，集中显示生效配置、捕获摘要、
  Cron 状态和 Minecraft 模拟任务；关闭模式时路由 404 且导航不可见。
- [ ] 增加独立视觉水印。
- [ ] 增加场景 seed、前端调试抽屉和可复制的脱敏诊断摘要。
- [ ] 若项目引入指标端点，再在后台概览/系统信息与该端点暴露同一状态；当前没有
  Prometheus endpoint，因此不虚构 `mcweb_developer_mode` gauge。
- [ ] 持久审计模式开启、关闭和配置变化。

#### D6：测试门禁（部分完成）

- [x] 覆盖 parser、禁用恢复、production 启动期 runtime、CORS 和 Puma/Vite 配置。
- [x] 覆盖身份 bypass、自动登录不提权、附件扫描/配额、支付 fake-only 与签名边界。
- [x] 覆盖 Webhook/Web Push 脱敏捕获以及 Web Push 不加载 VAPID/不访问网络。
- [x] 覆盖 Minecraft task/皮肤模拟与 Marketplace local-only 来源边界。
- [ ] 为每个声明 capability 补齐“关闭保留生产行为、开启只绕过目标”的成对测试。
- [ ] 完成 localhost、局域网、公网 IP、域名、HTTP、HTTPS、反向代理浏览器矩阵。
- [ ] 扩展 RBAC、私密附件、私信和管理后台的 Developer Mode 越权回归矩阵。
- [ ] 增加自动登录、fake 支付、邮件、Webhook 和 Web Push 的浏览器 E2E。

## 4. CE 尚未完成的代码阶段

### C0：生产运行与发布代码闭环

这里只规划仓库内仍需编写的配置、脚本和自动化代码：

- [x] 新增 `.dockerignore`，排除 `config/local*.yml`、`.env*`、日志、存储和开发产物。
- [x] Docker 使用明确的一次性 migration 服务或带数据库锁的迁移入口。
- [x] 启动配置拒绝默认密码、占位密钥和缺失的必要数据库。
- [x] 镜像改为多阶段构建，并以非 root 运行。
- [x] Web、Worker、数据库、Redis 和存储增加可判定的 healthcheck。
- [x] 备份/恢复代码覆盖数据库、对象存储清单和加密配置，包含校验和及空库恢复。
- [x] 更新/回滚脚本在切换 release 前完成兼容检查，失败时不切换流量。
- [ ] 增加“全新安装、升级、备份、恢复”的自动化真实基础设施验收环境。

仓库内第一批安全闭环已完成：备份使用 PostgreSQL custom dump、Active Storage
本地归档或对象清单、非密钥配置、外部公钥加密配置/不可变 secret 引用和完整
SHA-256；恢复默认只验证，实际执行要求精确确认、空库和不存在的目标；更新/回滚在
切流前执行候选与旧版本兼容检查，并在切流后就绪失败时尝试切回。实现合同见
[`PRODUCTION_BACKUP_AND_RELEASE.md`](PRODUCTION_BACKUP_AND_RELEASE.md) 和
`test/lib/mcweb/production_recovery_contract_test.rb`。真实 PostgreSQL、对象存储、
systemd、Redis 及故障恢复演练仍属于未完成验收，不能因合同测试通过而视为 C0 完成。

验收：

- 空环境一次启动完成建库，重复启动不会重复迁移。
- 镜像层和发布包中不存在本地配置或密钥。
- 对数据库、Redis、Worker 和存储分别故障注入时，健康状态准确。
- 自动完成一次备份和恢复，并比对订单、权限和附件清单。

### C1：附件安全与生命周期

当前内容识别、配额和清理代码已有部分实现，下一阶段只补齐缺口：

- [x] PNG/JPEG 完整解码后重新编码；限制输入/输出字节、8192 单边和 800 万
  总像素，JPEG 去元数据并拒绝 progressive、多扫描、拼接、截断和 EOI 后尾随载荷。
- [x] 定义恶意文件扫描 adapter、隔离状态、超时、重试和安全失败状态。
- [x] 用户、身份组、站点三级容量/数量/频率配额及并发预留。
- [x] 清理未绑定、过期、扫描失败和已删除内容对应的 Blob。
- [x] 私密附件下载、缓存头、对象存储 key 和直链场景权限回归。
- [x] 管理后台增加隔离队列、扫描结果、配额占用和清理记录，并提供桌面表格与
  移动卡片两套 Arco 响应式视图。
- [x] 以独立权限提供审计化重新扫描和清理重试入口；重新扫描期间继续 fail closed。
- [ ] 为确认的扫描误报设计独立人工放行策略、理由和审计，不复用重新扫描动作。

验收：

- 伪 MIME、畸形图片、图片炸弹、扫描超时和并发上传均有自动测试。
- 内容事务失败不会留下永久 Blob 或已计费配额。
- Developer Mode 绕过扫描时仍保留 `dev_bypassed` 可观察状态。

### C2：支付与退款完整闭环

当前未提交代码中已经开始接入官方 Stripe SDK；后续不再重写 provider，而是完成：

- [x] Webhook 失败重试、dead-letter、人工重放和 processing 超时恢复。
- [x] 晚到支付、孤儿支付和订单已取消后到账的人工处理队列。
- [x] 部分/累计/并发退款金额守恒。
- [x] 库存、优惠券、礼品卡、余额、会员和数字权益恢复的可重入处理。
- [x] 支付渠道配置页、凭证加密、连接测试、账户身份绑定和 Webhook 配置检查。
- [x] 支付、Webhook、退款、失败任务及人工动作统一后台。
- [x] 每日支付/退款对账任务及差异处理。
- [ ] 将尚未纳入现行后台的人工余额/权益调整也统一到独立权限、二次确认和
  不可变审计；现有重放、渠道配置及对账复核动作已具备权限和确认令牌。

验收：

- Stripe test mode 完成支付、取消、失败、异步成功、重复回调、晚到支付、
  部分退款、全额退款及进程中断恢复。
- 任何重试不会重复发货、重复退款或重复恢复权益。
- Developer Mode 只能调用 fake provider，不能加载 live credentials。

### C3：公网滥用与查询规模

- [x] 所有限流响应统一返回 `Retry-After`、错误码和剩余时间。
- [x] 限流策略支持账号、IP、资源和操作组合，并可配置与观测。
- [ ] 如有合规且必要的产品设计，再增加设备维度；当前不采集浏览器指纹。
- [x] 审查全文搜索、建议、热门榜单、未读、通知和后台列表查询计划。
- [x] 修复已识别的 N+1、无界结果集和缺少索引的高频路径。
- [x] 建立匿名、普通会员、受限会员、版主、管理员权限回归矩阵。
- [ ] 增加桌面、移动端、长文本、大图片、空数据和大数据量场景。

### C3.1：共享权限目录与全局身份组

- [x] 用单一核心目录描述权限键、状态、后台模块、I18N 和真实执行点；seed、
  后台角色页和身份组编辑器不再维护彼此漂移的权限列表。
- [x] 核心保留键与插件贡献键分开处理；插件不得占用核心命名空间，已停用或
  遗留键只能保留/撤销，不能重新授予。
- [x] 将全局身份组写操作集中到事务服务，分别检查组管理、成员分配和权限管理，
  并限制非站主只能委派自己拥有的有效权限。
- [x] 身份组创建、更新、删除、成员加入/移除和主组切换记录不可变审计快照；
  数据库约束与服务共同维持每名成员最多一个且在仍有组关系时至少一个主身份组。
- [x] 身份组后台提供分类权限编辑、成员分页和与后端一致的操作能力；用户详情页
  提供账号类型、角色与包括身份模块在内的后台模块授权入口。
- [x] 迁移为既有论坛身份组管理员补授身份模块，并保持重复执行安全。
- [x] Ruby 服务、控制器、迁移和前端源码测试覆盖越权委派、旧权限撤销、主组
  提升、成员提权和 staff 模块访问。
- [x] 将角色查看与角色管理从系统设置权限中拆出；角色权限变更使用与身份组相同
  的可分配目录和“只能委派自身已有权限”边界，并禁止非站主管理超出自身权限的角色。
- [x] 升级迁移同时兼容角色授权和身份组 JSONB 授权；既有论坛身份组管理员保留
  四类身份组能力，符合条件的 staff 同步获得身份后台模块，重复执行不产生重复授权。
- [x] 将 IP/邮箱封禁、论坛信任等级和商城余额调整拆成独立权限；`admin.access`
  仅代表进入后台，不再作为论坛、商城或安全写操作的万能兜底。
- [x] 后台导航按每个入口的实际模块与权限过滤；位于论坛/商城分组中的系统配置
  入口使用系统模块门禁，避免“菜单可见但后端拒绝”或“可直达但菜单隐藏”。

### C4：审核与数据生命周期

- 统一待审核、举报、垃圾清理、附件隔离和用户风险视图。
- 批量移动、删除、警告、封禁及隐私删除补齐权限、幂等和审计。
- 建立内容保留、软删除、永久删除、管理员保全和用户数据导出策略。
- 危险操作统一二次确认和 request id，禁止只依赖前端隐藏。

### C5：商城运营完整性

- 库存流水、人工调整原因和库存预留/超时释放。
- 异常订单和异常库存恢复视图。
- 履约任务 dead-letter、重试次数、人工重放和执行结果审计。
- 争议、拒付和支付风控状态机。
- 税费、发票、退款凭证、财务导出和订单保留策略。
- 对库存、订单、优惠券、礼品卡、余额及会员执行并发和故障注入测试。

### C6：I18N、可访问性和质量门禁

- [x] CI 检查 Rails locale 键集合、缺失翻译和生产 fallback。
- [ ] 检测业务 Vue/Ruby 代码中的硬编码用户文案。
- [ ] 人工复核资金、权限、审核和安全错误翻译。
- [ ] 键盘、焦点、ARIA、对比度、Reduce Motion 和移动端验收。
- [x] 将全部 Node 测试纳入 CI，而不是只在本地执行。
- [ ] 增加 Playwright 系统 E2E 和稳定截图基线。

### C7：可观测与运行状态代码

只实现应用代码部分：

- [x] Readiness 检查数据库、真实存储写读、生产 Worker 进程存在性和队列状态。
- [ ] 增加独立 Worker 心跳与队列等待时长阈值，不能只依赖进程列表和积压计数。
- [x] Liveness 不受 Minecraft 节点等业务降级影响。
- [ ] 增加请求延迟、慢查询、队列积压、邮件、Webhook、上传和支付指标。
- [ ] 为异常上报提供 adapter 和敏感字段过滤。
- [ ] 后台显示关键依赖、失败任务和容量趋势。

## 5. 依赖关系

```text
Developer Mode foundation
  ├─ identity/request bypasses
  ├─ external-service recording adapters
  └─ developer diagnostics

Attachment lifecycle
  └─ moderation/admin views

Stripe/Webhook reliability
  ├─ refund invariants
  ├─ entitlement restoration
  └─ reconciliation/admin views

Abuse + query scale
  └─ E2E/load/fault tests

Production runtime/release code
  └─ clean install/upgrade/restore acceptance

CE candidate commit
  └─ merge exact CE history into EE
```

## 6. 每阶段完成定义

- 代码、数据库 migration、权限键、路由、前端动作和测试同时完成。
- 不保留只有按钮没有后端实现的占位功能。
- 新 migration 只能追加，不修改已经进入发布历史的 migration。
- 新增写操作具备服务层鉴权、事务/幂等、审计和失败恢复。
- 中英文键、错误码和 API 文档同步。
- RuboCop、Rails、Node、前端生产构建和安全扫描全部通过。
- 工作树干净，提交基于最新 CE `main`。

## 7. 已确认决策

1. Developer Mode 是 `config/local.yml` 中的配置总开关，不使用数据库
   SiteSetting。
2. 开启后可从任意地址、网络、协议和反向代理访问，不增加 loopback、CIDR、Host、
   或来源限制；production 必须额外提供固定的精确确认短语以防误开。
3. production 确认变量不单独开启模式，且普通 `true`、`yes` 或近似值必须
   fail-closed。
4. `unrestricted` preset 默认关闭 CSRF、CSP、Host/Origin、邮箱验证、TOTP、限流、
   锁定、反垃圾、上传扫描等会阻碍开发的验证，并关闭生产缓存和资产优化。
5. 外部服务默认使用本地 fake/capture/simulate adapter；连接真实测试沙箱必须
   逐项显式开启，live 凭证不得自动加载。
6. 自动登录和身份切换属于可选配置，不因 Developer Mode 开启而默认冒充某个用户。
7. 身份组、资源归属、数据库约束、事务、幂等和金额状态机等功能正确性边界默认
   保留；临时权限覆盖必须单独、显式开启并持续显示。
