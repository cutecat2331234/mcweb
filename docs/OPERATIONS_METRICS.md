# McWeb CE 运行指标与容量趋势

> 状态：应用代码已实现
> 最近复核：2026-07-29
> 适用范围：CE 共享运行底座；EE 应通过完整 CE 提交历史继承

## 1. 目标与边界

本模块提供低开销、匿名、持久的应用运行指标，以及
`/admin/system/jobs` 中的容量趋势。它用于回答请求是否变慢、5xx 是否增加、
数据库是否出现慢查询、后台任务或邮件是否失败、支付 Webhook、社区上传和附件扫描
是否健康，以及队列容量是否接近阈值。

它不是：

- 用户行为画像、广告分析或跨站追踪；
- 日志、Tracing、APM 或 Prometheus 兼容端点；
- 对 SQL、请求 URL、Webhook 载荷、邮件内容或附件内容的存档；
- 取代外部告警、值班、容量压测和事故响应流程的完整监控平台。

## 2. 数据流

```text
ActiveSupport::Notifications / QueueSnapshot
  -> 严格指标与维度白名单
  -> 每进程有界内存缓冲
  -> 分钟边界或每分钟 FlushMetricsJob
  -> PostgreSQL ON CONFLICT 原子累加
  -> 有界聚合查询
  -> Jobs 后台 Arco 趋势视图
```

每个 Web/Worker 进程只在内存中合并当前分钟、指标名和维度摘要相同的样本。
`Operations::Metrics::Buffer` 在下一分钟的首个样本到来前先刷新旧批次；
Sidekiq 另外每分钟执行 `Operations::FlushMetricsJob`，刷新该 Worker 进程并记录队列
容量。不会在请求回调里逐条写数据库。

数据库唯一键是：

```text
bucket_at + metric_name + dimensions_key
```

`dimensions_key` 是规范化白名单维度 JSON 的 SHA-256。写入使用单条
`INSERT ... ON CONFLICT DO UPDATE` 语义，`sample_count` 与 `value_sum` 累加，
`value_min`/`value_max` 分别取最小和最大值。多个 Web/Worker 进程写同一分钟时不会
以最后写入者覆盖先前样本。

刷新时会先用互斥锁交换出批次，再在锁外写数据库；新请求仍可继续记录。数据库写入失败
时，旧批次会与期间新到的同键样本重新合并，等待下一次刷新。缓冲区默认最多
512 个不同键；超过硬边界的新键会被拒绝并增加进程内 `dropped_samples`，不会无限占用
内存。当前目录的闭集维度数量远低于这个上限。

目录自身也限制为最多 512 个理论维度组合，并与默认缓冲键上限保持一致；单个指标最多
4 个维度、每个维度最多 16 个固定值、单指标最多 256 个组合。目录规模在启动时计算，
超限会直接阻止应用启动，而不是等流量进入后丢弃不可预测的一部分指标。

尚未刷新的当前分钟仍属于进程内易失状态。操作系统强制终止或断电可能丢失该分钟尚未
刷新的样本；本模块不为了运行指标给每个业务请求增加同步持久化开销。

## 3. 指标目录与隐私合同

持久层只接受以下指标和低基数维度：

| 指标 | 允许维度 | 说明 |
|---|---|---|
| `request.duration_ms` | `surface`, `outcome` | 请求时长；surface 只可能为 admin/api/app/website/other |
| `request.server_error` | `surface` | HTTP 5xx 次数 |
| `database.slow_query.duration_ms` | 无 | 超过阈值的查询时长 |
| `job.execution.duration_ms` | `queue`, `outcome` | Active Job 执行时长 |
| `job.failure` | `queue` | Active Job 失败次数 |
| `mail.delivery.duration_ms` | `outcome` | Action Mailer 投递时长 |
| `mail.failure` | 无 | 邮件失败次数 |
| `payments.webhook.processed` | `provider`, `outcome` | 支付 Webhook 处理结果 |
| `community.upload.event` | `event`, `kind` | 上传预留、存储、配额拒绝和清理生命周期 |
| `community.scan.event` | `outcome` | 附件扫描 clean/infected/error/retry |
| `queue.enqueued` | 无 | 当前队列积压 |
| `queue.oldest_wait_seconds` | 无 | 最长排队时间 |
| `queue.utilization_percent` | 无 | Worker 并发利用率 |
| `queue.worker_count` | 无 | Worker 进程数 |

所有维度都有固定允许值；未知值归一为 `other`。调用方多传的键会被忽略，不会被序列化。
以下内容禁止进入指标表：

- user id、用户名、邮箱、IP、会话或设备标识；
- URL、路径、查询参数、Referer；
- SQL、bind 参数、表中字段值；
- Webhook payload、event id、错误正文；
- 邮件地址、主题、message id 或正文；
- 文件名、附件内容、扫描器错误正文；
- token、Cookie、Authorization、密码、密钥或绝对路径。

采集回调失败只记录异常类名，不记录通知 payload，也不会中断业务请求。

### 3.1 下游版本的启动期扩展

EE 等下游版本不需要修改 CE 的 `Catalog::DEFINITIONS`。下游可在一个排在
`operations_metrics.rb` 之后的 initializer 中注册代码所有的 registrar：

```ruby
require Rails.root.join("lib/mcweb/operations_metrics_registrar_config")

registrar = lambda do |registry|
  registry.register(
    key: "enterprise.maintenance.run",
    type: :counter,
    dimensions: {
      outcome: %w[success failure other],
      mode: %w[automatic manual other]
    }
  )
end

Mcweb::OperationsMetricsRegistrarConfig.register!(
  Rails.application.config.x,
  registrar
)
```

类型只允许 `counter`、`distribution`、`gauge`。指标键、维度键和维度值只接受小写
静态 token；每个有维度的定义必须显式包含 `other`，以便未知采样值安全归一。等价的
重复定义幂等，名称相同但类型或维度不同会 fail closed。生产进程在启动收口时执行
registrar，随后 registrar 列表和指标目录都会冻结；开发环境代码重载只会从这份已冻结
列表重建目录。请求或任务运行期间没有注册 API，未知指标键只会被忽略，不会创建新目录
项或缓冲键。

## 4. 采集来源

- `process_action.action_controller`：请求时长和 5xx；
- `sql.active_record`：仅在超过慢查询阈值时记录时长，忽略 cache、SCHEMA 和
  TRANSACTION；不复制 SQL/binds；
- `perform.active_job` 以及 retry/discard 事件：执行时长、未处理异常和被
  `retry_on`/`discard_on` 接管的失败尝试；同一次尝试只累计一次失败；
- `deliver.action_mailer`：投递时长与异常结果；
- `payments.webhook.processed`：provider 与稳定 outcome；
- `community.upload.*` 的闭集事件：上传预留、存储、配额拒绝、清理和清理重试；
- `community.attachment.scan_*` 的闭集事件：clean、infected、error 和 retry；
- `Operations::QueueSnapshot`：每分钟队列容量样本。

## 5. 阈值配置

所有值都经过范围校验；缺失或越界时回退默认值。

| 环境变量 | 默认值 | 用途 |
|---|---:|---|
| `MCWEB_SLOW_QUERY_WARNING_MS` | 250 | 慢查询采样阈值 |
| `MCWEB_REQUEST_LATENCY_WARNING_MS` | 1000 | 平均请求延迟告警 |
| `MCWEB_REQUEST_ERROR_RATE_WARNING_PERCENT` | 1 | 5xx 比率告警 |
| `MCWEB_JOB_FAILURE_RATE_WARNING_PERCENT` | 5 | 后台任务失败率告警 |
| `MCWEB_MAIL_FAILURE_RATE_WARNING_PERCENT` | 5 | 邮件失败率告警 |
| `MCWEB_QUEUE_UTILIZATION_WARNING_PERCENT` | 90 | 队列并发利用率告警 |
| `MCWEB_QUEUE_BACKLOG_WARNING` | 1000 | 队列积压告警；与现有 QueueSnapshot 共用 |

后台将阈值分为 healthy、warning、critical；critical 通常为告警阈值的 2–5 倍，
队列利用率为 1.1 倍。这个状态只用于快速分诊，不等同于外部告警通知。

## 6. 趋势查询预算

Jobs 页要求 `system.jobs.read`，时间范围可选 `1h`、`6h`、`24h`、`7d`、`30d`。
范围切换通过 Inertia `only: ['operationsMetrics']` 局部获取，不硬刷新、不重新挂载整页，
并保留滚动位置和页面状态。

查询在 PostgreSQL 中先按固定分辨率聚合：

| 范围 | 分辨率 |
|---|---:|
| 1 小时 | 5 分钟 |
| 6 小时 | 15 分钟 |
| 24 小时 | 1 小时 |
| 7 天 | 6 小时 |
| 30 天 | 1 天 |

一次查询同时覆盖当前范围与等长上一范围，用于显示环比。最多读取 5,000 个聚合行；
查询使用 5,001 行作为超限探针，一旦超过预算就 fail closed，返回
`query_budget_exceeded`，不展示不完整趋势。页面只接收聚合计数、平均/最大值、状态和
时间桶，不接收原始样本。

## 7. 保留与清理

`Operations::CleanupMetricBucketsJob` 每天 03:25 执行。默认保留 30 天，可通过
`MCWEB_OPERATIONS_METRICS_RETENTION_DAYS` 配置为 7–365 天。每批删除 1,000 行，
单次最多 100 批，避免一次清理长期占用数据库；若积压超过单次预算，后续每日任务继续
清理。

## 8. 验证

共享 PostgreSQL 测试库准备迁移后，可执行：

```powershell
$env:RAILS_ENV = "test"
$env:PARALLEL_WORKERS = "1"
bundle exec ruby bin/rails test `
  test/services/operations/metrics `
  test/models/operations/metric_bucket_test.rb `
  test/jobs/operations/flush_metrics_job_test.rb `
  test/jobs/operations/cleanup_metric_buckets_job_test.rb `
  test/integration/admin/jobs_admin_test.rb
npm run test:javascript -- --test-name-pattern="operations"
npm run typecheck
npm run check:i18n
```

覆盖重点：

- 多线程缓冲聚合与数据库冲突写原子累加；
- 刷新失败后批次恢复并与新样本合并；
- 硬键数量上限；
- URL、SQL/binds、user id、邮箱、token 等敏感载荷不进入持久维度；
- 当前/上一范围汇总、查询次数和 5,000 行预算；
- 保留清理边界；
- Jobs 页 Arco 组件和局部 Inertia 范围切换。
