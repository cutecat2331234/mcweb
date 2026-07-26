# 社区查询计划运维基线

> 适用范围：McWeb CE、PostgreSQL 18
> 最后复核：2026-07-26

本文是全文搜索、搜索建议、热门榜单、未读统计和通知聚合的现行查询计划
基线与复核手册。相关查询或数据分布发生明显变化时，应更新本文并重新执行
隔离样本验证。

## 现行查询与索引

| 查询族 | 现行实现 | 主要索引/约束 |
|---|---|---|
| 全文搜索 | 标题和正文使用 `simple` 配置的 `tsvector` 表达式查询 | 既有 `index_forum_topics_on_title_tsvector`、`index_forum_posts_on_body_tsvector` |
| 搜索建议 | 标题、用户、标签和分区的 `%ILIKE%` 使用 `pg_trgm`；每用户最多 20 条的保存搜索继续先按用户过滤 | `idx_*_suggest_*_trgm` |
| 热门榜单 | 先按时间窗口一次聚合帖子，再将每主题计数连接到主题；不再对每个候选主题分别执行 `EXISTS` 和 `COUNT` | `idx_forum_posts_top_window` |
| 未读统计 | 只把未软删除的已发布普通帖视为未读；用户/主题定位后执行楼层 `EXISTS` | 既有用户/主题唯一索引及 `idx_forum_posts_unread_floor` |
| 通知聚合 | 时间顺序、未读时间顺序和类型聚合分别使用匹配索引；五个期间计数合并为一个 `FILTER` 聚合查询 | `idx_notifications_user_created`、`idx_notifications_unread_user_created`、`idx_notifications_user_type_created` |

索引迁移为
`20260726125200_optimize_community_query_plans.rb`，使用 concurrent DDL，可回滚删除
本次索引。回滚不会删除 `pg_trgm` 扩展，因为同一数据库中的其他功能可能已共享它。

## 可重复的只读复核

在目标环境运行：

```powershell
$env:RAILS_ENV = "production"
bundle exec ruby scripts/audit-community-query-plans.rb
```

该脚本：

- 只执行 `EXPLAIN (FORMAT JSON)`，不使用 `ANALYZE`，不会执行查询或写入业务表；
- 使用封闭的固定合成搜索词和固定不存在的用户编号，不读取外部搜索内容或真实用户编号；
- 只输出节点类型、估算行数、成本、索引名和顺序扫描表名；
- 不输出原始 SQL、谓词、搜索词、用户标识符或数据库名。

小表或空库选择顺序扫描是正常行为。重点检查大表计划是否仍能看到对应索引，
以及热门榜单是否没有逐主题重复的聚合节点。需要真实耗时和缓冲区证据时，应在
脱敏的隔离数据库或只读副本中使用 `EXPLAIN ANALYZE`，不要在生产主库直接执行。

## 隔离样本证据

样本只使用合成内容，并在独立数据库中提交后执行 `VACUUM ANALYZE`。验证结束后
删除整个隔离数据库。耗时是本机方向性数据，不是生产 SLA；节点形态和索引选择才是
主要回归依据。

改造前样本为 2 万主题、10 万帖子和 10 万通知：

| 查询 | 改造前证据 |
|---|---|
| 全文标题 | 表达式 GIN，1.676 ms |
| 标题/用户/标签建议 | 顺序扫描，分别为 9.448 / 15.098 / 11.088 ms |
| 7 日热门 | 总成本 481638.14；相关聚合执行 7998 次；58.353 ms |
| 大量未读 | 主题、状态和帖子顺序扫描；32.269 ms |
| 未读通知流/30 日类型聚合 | 顺序扫描，分别为 88.688 / 19.719 ms |

改造后样本为 4 万主题、20 万帖子和 20 万通知：

| 查询 | 改造后证据 |
|---|---|
| 全文标题 | `index_forum_topics_on_title_tsvector`，0.145 ms |
| 标题/用户/标签建议 | trigram GIN，分别为 0.114 / 0.660 / 0.416 ms |
| 分区建议 | 2000 行时规划器保留顺序扫描，2.118 ms；这是小表的合理选择 |
| 7 日热门 | `idx_forum_posts_top_window`；无逐主题重复聚合；总成本 9434.20，43.554 ms |
| 500 个未读主题 | 用户索引加楼层索引探测，10.110 ms |
| 4 万个未读主题 | 规划器选择一次 Hash/Semi Join 和顺序扫描，93.067 ms；没有相关聚合循环 |
| 未读通知流/30 日类型聚合 | 专用通知索引，分别为 0.133 / 2.724 ms |

## 继续监测的边界

- 大量未读时，一次扫描比数万次随机索引探测更便宜，因此 PostgreSQL 可能有意选择
  Hash/Semi Join。持续观察此页面的 p95 和扫描行数；若单用户未读规模继续上升，应
  再评估物化未读计数或分段缓存，而不是强制索引提示。
- 搜索词命中比例很高或表很小时，trigram 查询仍可能选择顺序扫描，这是成本模型的
  正常结果。
- 热门榜单仍会扫描所选时间窗口内的合格帖子。P2 容量阶段可依据真实窗口基数考虑
  预聚合或短 TTL 缓存。
- 查询计划测试只验证 SQL 形态、索引 valid/ready 状态和脱敏报告契约，不绑定脆弱的
  精确 cost。

聚焦自动测试：

```powershell
bundle exec ruby bin/rails test `
  test/services/operations/community_query_plan_audit_test.rb `
  test/services/community/notification_period_counts_test.rb `
  test/integration/community_top_test.rb
```
