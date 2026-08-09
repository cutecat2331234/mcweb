# 数据库 Schema 交付合同

McWeb 继续使用 Rails 的 `db/schema.rb` 作为 fresh database 的初始化来源。迁移中创建的
PostgreSQL 用户触发器及其触发器函数属于数据库约束的一部分，不得只存在于已经运行过
历史迁移的数据库中。

CE 在 schema dump 阶段扩展 PostgreSQL 的 Ruby schema 导出器：

- 导出目标 schema 内普通表或分区表上的非内部触发器；
- 在触发器之前导出其用户定义函数；扩展拥有的函数由 `enable_extension` 恢复，不重复创建；
- 保留触发器的 disabled、always 或 replica 状态；
- 遵守 Rails 的 ignored tables 配置，不导出被排除表的触发器；
- fresh `db:schema:load` 不需要 `pg_dump` 或 `psql`，Windows、本地安装与 CI 维持原有入口。

开发者创建或修改触发器后必须运行：

```bash
bin/rails db:migrate
bin/rails db:schema:dump
git diff --check db/schema.rb
```

`db/schema.rb` 应出现 `User-defined PostgreSQL trigger functions and triggers` 区段。禁止手工
编辑该区段；它来自当前数据库 catalog。CI 的 schema consistency 检查会继续阻止漏交 schema。

合同测试会在隔离 PostgreSQL schema 中创建 append-only 触发器，执行 Ruby schema dump，删除
原 schema，再加载导出文本并验证数据库仍拒绝更新。这同时覆盖显式 `db:schema:load` 和 fresh
`db:prepare` 使用的同一 schema 来源。
