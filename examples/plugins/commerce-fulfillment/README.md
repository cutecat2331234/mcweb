# Commerce Fulfillment reference plugin

This installable CE plugin listens to the stable `commerce.order.paid`
after-commit event, derives a deterministic idempotency key, and dispatches a
plugin-owned job with bounded retries. The example raises a temporary provider
failure when requested by its test input and succeeds on a later attempt.

It also registers the provider ID
`examples/commerce_fulfillment:direct`. Select that ID in a product's
`fulfillment_config.plugin_provider`; optional JSON-safe configuration belongs
in `fulfillment_config.provider_options`. Options are static product
configuration and must not contain credentials, customer data, or
order-derived templates.

The provider receives a frozen request containing:

- `delivery_id`, which remains stable across retries;
- the current attempt number and idempotency key;
- allow-listed order status, total, and currency;
- allow-listed item/product/variant identifiers, quantity, and amounts;
- the configured `options`.

The host never injects a username, email, address, payment/provider reference,
credential, or arbitrary order metadata. A provider must deduplicate external
work with `delivery_id` and return only one of:

```ruby
{ status: "succeeded", external_reference: "..." }
{ status: "retryable", error_code: "provider_timeout" }
{ status: "failed", error_code: "invalid_destination" }
```

The core then emits the stable `commerce.fulfillment.dispatched`,
`.retryable_failed`, `.failed`, `.completed`, or `.cancelled` after-commit
event for the authoritative transition. Those payloads are also allow-listed
and contain no provider metadata or raw response.

It intentionally contains no WebSocket or realtime code.

## 中文说明

此 CE 参考插件同时演示两条推荐路径：监听 `commerce.order.paid` 后用订单 public ID
创建幂等插件任务；以及注册
`examples/commerce_fulfillment:direct` 自定义履约渠道。商品配置写入
`fulfillment_config.plugin_provider`，额外的 JSON 配置写入 `provider_options`。

provider 请求只有稳定 `delivery_id`、attempt、订单/商品的安全字段和 `options`，没有
宿主注入的用户身份、邮箱、地址、支付信息、密钥或任意 metadata；静态
`provider_options` 也不得人工写入这些内容。返回值只允许
`succeeded/retryable/failed` 与受限的 `external_reference/error_code`。外部调用必须用
`delivery_id` 幂等；实时/WebSocket 代码不属于 CE。

```sh
bin/mcweb-plugin test examples/plugins/commerce-fulfillment --json
bin/mcweb-plugin release examples/plugins/commerce-fulfillment --json
```
