# 通用安全证据附件生产合同

## 所有权与边界

本能力归属 **McWeb CE**。文件内容识别、上传配额、恶意软件扫描、隔离、保留、
清理、授权下载、审计以及身份生命周期都是可被多个产品复用的平台能力；PVP 的复审、
复议、处罚申诉等业务含义仍只属于 EE-PVP。

继承方向保持 `CE -> EE -> EE-PVP`。下游只能通过本合同公开的注册表和服务接入业务
主体，不得复制扫描器、另建 raw Active Storage 下载地址或把 PVP 类型放进 CE。

## 任务清单

1. 建立冻结式主体注册表和启动期 registrar API。
2. 建立证据附件元数据、上传关联和不可变事件账本的数据库约束。
3. 复用 `Community::AttachmentContentInspector`、`Community::UploadQuota`、
   `Community::AttachmentMalwareScanner` 与既有清理队列完成上传生命周期。
4. 提供幂等创建、扫描状态查询、授权下载和到期清理服务。
5. 把证据附件元数据接入身份数据导出和关户生命周期注册表。
6. 提供下游可直接调用的控制器无关服务边界，并为通用 HTTP API 设置同一授权策略。
7. 覆盖注册表、授权、配额、内容识别、扫描失败、隔离、并发幂等、下载、保留、
   清理、身份生命周期、数据库约束和迁移往返测试。

## 主体注册表合同

每个下游业务主体必须在 Rails 启动期注册一个唯一 `subject_key`，例如
`pvp.review_request`。注册项必须包含：

- 稳定的 Active Record `model_name`；
- 根据主体公开 ID 解析记录的 resolver；
- 分离的上传授权和下载授权 callable；
- 返回绝对保留截止时间的 retention callable；
- 每文件字节上限、每主体文件数上限和每主体总字节上限；
- 明确的允许扩展名子集。

注册表在启动完成后冻结。重复 key、重复 model、非法 key、非 callable、超出平台硬上限、
不受内容识别器支持的扩展名或运行时注册一律立即失败。授权 callable 只有严格返回
`true` 才算通过；异常、空值和其他返回值全部 fail closed。

CE 对外公开的稳定入口是：

- `SecureEvidence::SubjectRegistry#register`
- `SecureEvidence::SubjectCatalog.entry_for_key`
- `SecureEvidence::CreateAttachment.call`
- `SecureEvidence::AttachmentAccess.upload_allowed?`
- `SecureEvidence::AttachmentAccess.download_allowed?`
- `SecureEvidence::PurgeAttachment.call`

HTTP 层只接收主体 key、主体公开 ID、文件和幂等键，不接收 Ruby 类名或 Active Storage
标识。下游可以复用通用端点，也可以在自己的控制器中直接调用服务，但不能绕过服务。

## 上传与状态合同

- 文件必须先通过服务端实际字节和结构识别；客户端 MIME 永不可信。
- 主体注册项只能收紧 CE 支持的格式和限制，不能扩大平台允许类型或硬上限。
- 每文件最大 10 MiB、每主体最多 20 个文件、累计最多 100 MiB；注册项必须设置不超过
  这些硬上限的正整数。
- 附件创建和 upload reservation 在同一数据库事务内绑定；Blob 存储失败必须安排可重试
  清理，不能留下不计配额的 Blob。
- 创建请求必须提供规范幂等键。相同上传者、主体和幂等键的完全相同请求返回同一附件；
  载荷指纹不同则返回冲突，不能静默覆盖。
- 创建后状态为 `pending`；只有真实扫描 clean 后为 `available`。infected、扫描器未配置、
  断连、超时、完整性错误和未知异常均不可下载。
- infected 或重试耗尽的 error 进入 `quarantined`，由保留规则和清理任务处置；开发模式
  bypass 只能沿用现有显式开发模式边界，关闭后立即重新 fail closed。
- 证据元数据不物理删除。Blob 清理后状态为 `purged`，保留文件名、大小、摘要、主体、
  上传者快照和账本，便于说明发生过什么。

## 授权与下载合同

- 上传者必须已登录、主体可解析且注册项明确授权；不存在和无权访问对外均返回同一不可见
  结果，避免主体枚举。
- 下载每次重新解析主体并重新执行下载授权，不缓存历史授权决定。
- 下载必须同时满足：附件未清理、扫描结果当前可信、Blob 存在、主体仍可解析、授权返回
  `true`。任一检查或适配器异常均拒绝。
- 客户端永远只得到应用内的稳定下载路径。禁止输出 Active Storage signed URL、service URL
  或 blob key。
- 响应强制 `attachment`、可信服务端 Content-Type、`nosniff`、CSP sandbox、
  same-origin 和 `private, no-store`，并通过应用进程流式传输。
- 下载成功写入不可变事件和平台审计记录；审计元数据不得包含文件内容、Blob key、扫描器
  原始输出或其他秘密。

## 保留、隔离与关户合同

- 注册项在创建时给出绝对 `retention_until`，范围必须在创建时间后 1 小时至 10 年内。
- 到期不是自动授权删除：清理时必须重新解析主体并调用 retention；适配器异常、主体仍要求
  延长保留、数据治理 hold 或扫描仍在重试时均停止清理。
- 主体已被合法删除且没有 hold 时，使用已固化的截止时间；不能因主体解析失败提前删除。
- 用户数据导出包含其上传证据的公开 ID、主体 key/公开标识快照、文件元数据、摘要、状态、
  扫描时间、保留截止时间和事件时间线，不包含 raw Blob URL 或其他用户的私密数据。
- 关户 preflight 明确报告证据总数、已到期数和必须保留数。关户不会在账号事务中删除 Blob，
  也不会破坏仍受保留规则保护的证据；账号匿名化后保留稳定上传者公开 ID 快照。已到期、
  未 hold 的附件仍由保留调度器幂等清理，关户贡献不得把仍保留的附件描述为已删除。

## 审计和数据库不变量

- 元数据表对 public ID 唯一、幂等作用域唯一、大小与状态闭集、主体 key 格式、摘要格式、
  时间顺序及 Blob/upload 绑定建立数据库约束。
- 事件表仅允许闭集事件，幂等键全局唯一，JSON 必须为 object；数据库触发器拒绝 UPDATE
  和 DELETE，避免绕过模型后篡改。
- 创建、扫描 clean/infected/error、授权下载、保留延期、清理安排、清理成功/失败均追加事件。
- 状态变化与相应事件在同一数据库事务内完成；审计写入失败不得把可下载状态暴露给用户。

## 验收标准

- 注册表正确冻结并拒绝所有非法/重复/过宽注册。
- 上传对伪造 MIME、可执行签名、畸形归档、超限文件、超文件数、超累计字节均 fail closed。
- 相同幂等请求在串行与并发下只创建一个附件；不同指纹复用键返回冲突。
- 扫描器 clean 前、infected、error、开发 bypass 失效后、Blob 丢失、主体丢失或权限撤销后
  均无法下载。
- 授权下载不泄露 Active Storage URL，响应安全头完整，并产生不可变事件和审计记录。
- 保留期、hold 和适配器故障阻止提前清理；到期清理只移除 Blob，保留审计元数据。
- 身份导出和关户贡献可由核心注册表发现，输出稳定且不泄密。
- 新迁移在 PostgreSQL 上执行真实 `down -> up` 往返；focused Rails 测试、RuboCop、
  Zeitwerk 与 schema dump 均通过。
