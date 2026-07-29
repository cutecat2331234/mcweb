# McWeb 插件开发

McWeb CE 插件是与宿主同进程运行的受信任 Ruby 代码，不是安全沙箱。插件应通过
Manifest、Host API、事件、任务和声明式 contributions 扩展宿主，避免修改核心类或
复制领域策略。CE 插件不得包含 WebSocket、Action Cable 或其他实时运行时代码；实时
能力只存在于 EE。

## 标准命令

仓库提供 `bin/mcweb-plugin`，同时提供等价的 `rake plugin:*` 任务：

```sh
bin/mcweb-plugin create vendor/plugin --root ./plugins --json
bin/mcweb-plugin validate ./plugins/vendor/plugin --plugins-root ./plugins --json
bin/mcweb-plugin test ./plugins/vendor/plugin --json
bin/mcweb-plugin build ./plugins/vendor/plugin --output ./dist --json
bin/mcweb-plugin release ./plugins/vendor/plugin --output ./dist --json
bin/mcweb-plugin health ./plugins/vendor/plugin --json
bin/mcweb-plugin health vendor/plugin --installed --json
```

Rake 任务通过 `ID`、`PATH`、`TARGET`、`ROOT`、`OUTPUT` 等环境变量接收参数，并在
`JSON=1` 时输出相同 JSON 合同。每个 JSON 响应都包含
`schema_version/command/ok/data/warnings/errors`，失败进程返回非零退出码。

## 从创建到发布

`plugin:create` 生成严格的 `mcweb_plugin.yml`、入口文件、设置 schema、贡献目录、
英文和中文语言文件、合同测试、README 与 CHANGELOG。生成器不会覆盖已有目录。

`plugin:validate` 使用宿主自身的 Manifest 和 contribution loaders 校验：

- 插件 ID、SemVer、API 版本、依赖范围与能力兼容矩阵；
- entrypoint 存在、路径留在包内且 Ruby 语法有效；
- permissions、settings、jobs 和通用 contribution 文档；
- `mcweb_package.yml` 的插件身份及 Ruby/Rails/Plugin API 范围；
- 构建后的 `files.sha256` 文件清单、大小与 SHA-256。

`plugin:test` 先执行验证和隔离的宿主注册/激活/重置合同，再运行插件目录中的
`test/**/*_test.rb`。它还会扫描 CE 运行时代码，拒绝实时 WebSocket 引用。

`plugin:build` 过滤 Git 元数据、凭据、本机配置、缓存、日志和私钥，生成
`mcweb_package.yml` 与 `files.sha256`，再以固定时间戳和稳定文件顺序输出可复现 ZIP
及 `.zip.sha256`。官方参考插件默认保留测试；`--without-tests` 可排除测试。

`plugin:release` 要求 CHANGELOG 中存在当前版本的二级标题，随后生成 ZIP、校验和、
发布说明和 `.release.json`。`plugin:health` 可检查源码注册状态，或联合市场安装收据、
运行时 registry 与文件哈希检查已安装插件。

## Manifest 与扩展边界

当前 Manifest v1 接受 `id/name/version/api_version`，以及可选的
`description/author/homepage/requires/capabilities/contributions/entrypoint/setup`。
插件 ID 使用 `vendor/name`，所有 permission、event、translation、metadata 和
contribution ID 都必须留在由插件 ID 派生的命名空间内。

管理页面只使用安全 schema blocks（`stat`、`text`、`alert`、`links`、
`description_list`），不接受 raw HTML 或任意前端组件。管理页路径位于
`/admin/plugins/<vendor>/<name>/...`；公开页位于 `/plugins/<vendor>/<name>/...`。
UI slot 必须用 `target` 指向现有宿主页，避免贡献污染所有页面。

依赖已提交状态的邮件、Webhook、任务和其他外部副作用必须从 after-commit 事件触发。
任务必须声明参数 schema、最大尝试次数和租约，并使用稳定幂等键。插件只能消费 Host
API 的不可变 DTO，不应把 ActiveRecord 实例或内部异常作为公共合同。

## 商业事件与自定义履约

CE 提供稳定的商业 after-commit 事件，覆盖订单付款、支付确认/失败/退款、退款
申请/处理/拒绝、库存预留/释放/确认/调整，以及履约派发、可重试失败、终态失败、完成
和取消。它们只在权威状态转换提交后发布；回滚和服务幂等重放不会伪造第二个事件。
完整事件名、触发语义、幂等键和负载字段见
[`PLUGIN_SDK.md`](./PLUGIN_SDK.md#stable-commerce-events)。

所有商业事件都是固定白名单快照，不含用户身份、邮箱、地址、自由文本原因、支付渠道
引用、provider secret/metadata、原始 Webhook 或 Connector 响应。插件监听商业事件时
声明 `commerce.events.read`，需要发货时监听 `commerce.order.paid`，并用
`order.public_id` 创建幂等任务。

自定义交付渠道可在入口中注册：

```ruby
plugin.fulfillment_provider("direct") do |request|
  {
    status: "succeeded",
    external_reference: "vendor:#{request.fetch("delivery_id")}"
  }
end
```

在商品履约配置中设置
`plugin_provider: "<plugin-id>:<key>"`，可选配置写入 `provider_options`。请求只包含
稳定 `delivery_id`、attempt 的编号/幂等键、订单金额/币种/状态、商品/变体标识与数量、
以及 `options`，宿主不会注入 PII。`provider_options` 是静态商品配置，禁止写入密钥、
顾客数据或从订单动态插值的内容。返回值只能是：

- `status: "succeeded"`，可带最长 200 字符的 `external_reference`；
- `status: "retryable"`，必须带规范化 `error_code`；
- `status: "failed"`，必须带规范化 `error_code`。

处理器运行在后台履约任务中，必须用 `delivery_id` 对外部调用做幂等。声明
`commerce.fulfillments.write`；插件停用、provider 缺失、异常或非法返回都会转换成安全
且可观测的履约失败，不会把插件异常原文暴露给购买者。

## 官方 CE 参考插件

- [`examples/plugins/hello-event`](../examples/plugins/hello-event)：设置、事件、翻译和
  schema 管理页。
- [`examples/plugins/forum-extension`](../examples/plugins/forum-extension)：论坛字段、
  颗粒化审核权限和定向 UI action slot。
- [`examples/plugins/commerce-fulfillment`](../examples/plugins/commerce-fulfillment)：
  `commerce.order.paid` after-commit 事件、幂等履约任务、严格的自定义 provider 合同
  和失败重试。

三者均可直接执行 validate、test、build、安装、启停和卸载生命周期。EE 实时参考插件
必须只维护在 EE 仓库，不能合入 CE。
