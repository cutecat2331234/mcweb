# 生产备份、恢复、更新与回滚

> 最近复核：2026-08-22
> 适用范围：CE 原生 systemd/release 目录部署的仓库内安全合同
> 状态：脚本与隔离合同测试已实现；尚未在真实生产数据库、对象存储或 systemd 主机演练

## 安全边界

`bin/backup`、`bin/restore`、`bin/update` 和 `bin/rollback` 采用失败关闭：

- 不会把 `/etc/mcweb/mcweb.env` 明文复制进备份；
- 数据库、存储、配置或校验失败都会使整个操作失败；
- 恢复默认只验证，不能覆盖非空数据库、已有本地存储目录或已有配置文件；
- 更新在切换 `/opt/mcweb/current` 前完成候选版本启动检查、备份、迁移和旧版本
  回滚兼容检查；
- 更新或回滚切流后的服务/就绪检查失败时，会尝试原子切回原版本；
- 脚本不会自动执行数据库向下迁移。代码切回不等于数据库 schema 回退。

这些脚本不会读取后再输出密钥。命令日志、工单和文档中也不得粘贴
`DATABASE_URL`、私钥、解密后的环境文件或密钥管理系统返回值。

## 备份格式

每次成功备份会原子生成 `/var/backups/mcweb/<backup-id>/`，并在全部校验成功后
更新 `latest` 指针：

| 文件 | 内容 |
|---|---|
| `database.dump` | `pg_dump --format=custom` 数据库快照 |
| `active_storage_objects.ndjson` | `private_s3` 模式下每个独立对象快照的原键、备份键、字节数和 SHA-256 |
| `active_storage.tar.gz` | 仅本地盘模式下的文件归档 |
| `active_storage_files.sha256` | 仅本地盘模式下的逐文件 SHA-256 |
| `configuration.env` | 固定白名单中的非密钥配置 |
| `mcweb.env.gpg` | 使用外部 OpenPGP 公钥加密的完整配置，二选一 |
| `secret-config.reference` | 不可变密钥管理版本引用，二选一 |
| `backup-manifest.json` | 格式、备份 ID、时间与各类产物清单 |
| `SHA256SUMS` | 目录内全部正式产物的 SHA-256 |

`configuration.env` 不包含数据库密码、Rails/Lockbox 密钥、SMTP 密码、S3
访问密钥、Redis URL 或入站邮件密码。

`private_s3` 模式逐个读取 McWeb 数据库引用的 Blob，把对象本体写入独立的
`MCWEB_BACKUP_S3_BUCKET`/`MCWEB_BACKUP_S3_PREFIX/<backup-id>/objects/`，再从备份桶
下载并比对字节数与 SHA-256 后才发布备份。备份桶必须与主存储桶不同；已有同键
对象只会在内容完全相同时作为幂等重试复用，不同内容会以不可变冲突失败。该过程
不会扫描或复制数据库没有引用的孤儿对象。

备份桶仍必须由供应商侧启用私有访问、最小权限、加密、版本控制/对象锁、异地复制
和生命周期保护。仓库内 SHA-256 证明的是对象字节一致，不是供应商账户、KMS 密钥或
地域灾难后的可用性。

## 创建备份

私有对象存储部署必须先配置独立备份目标。静态凭据应由 root-only 环境文件或部署
平台 secret 注入；使用 IAM role 时可省略：

```bash
MCWEB_BACKUP_S3_BUCKET=mcweb-production-backups
MCWEB_BACKUP_S3_REGION=us-east-1
MCWEB_BACKUP_S3_PREFIX=mcweb-backups
# 非 AWS 兼容服务另设 MCWEB_BACKUP_S3_ENDPOINT=https://s3-backup.internal
# 及 MCWEB_BACKUP_S3_FORCE_PATH_STYLE=1
```

`MCWEB_BACKUP_S3_ACCESS_KEY_ID`、`MCWEB_BACKUP_S3_SECRET_ACCESS_KEY` 和可选
`MCWEB_BACKUP_S3_SESSION_TOKEN` 不会进入 manifest、恢复报告或安全配置副本。

### OpenPGP 公钥方式

备份主机只安装灾备公钥，解密私钥应保存在独立离线或受控恢复环境：

```bash
sudo gpg --import /secure-transfer/mcweb-backup-public-key.asc
sudo env MCWEB_BACKUP_GPG_RECIPIENT='<完整公钥指纹>' \
  /opt/mcweb/current/bin/backup
```

不得把私钥或私钥口令写入 `mcweb.env`。首次启用前应在隔离主机证明指定私钥可以
解密测试产物。

### 密钥管理系统引用方式

环境配置完全由 Vault、云 Secret Manager 等系统管理时，备份只存不可变版本引用：

```bash
sudo env MCWEB_SECRET_BACKUP_REFERENCE='vault://production/mcweb/versions/42' \
  /opt/mcweb/current/bin/backup
```

引用必须是仅含安全路径字符的 URI，并以 `/versions/IMMUTABLE_ID` 结尾；不能使用
`latest`、`current` 或 `active`，也不能把真实 secret 值伪装成引用。

### 旧本地盘模式

生产新部署必须使用私有对象存储；仅迁移旧实例时可显式归档本地目录：

```bash
sudo env MCWEB_ACTIVE_STORAGE_SERVICE=local \
  MCWEB_LOCAL_STORAGE_ROOT=/var/lib/mcweb/uploads \
  MCWEB_BACKUP_GPG_RECIPIENT='<完整公钥指纹>' \
  /opt/mcweb/current/bin/backup
```

本地目录含符号链接、设备或其他特殊文件时备份会拒绝继续。备份目录与本地存储
目录不得相同、互为父目录或互相包含，避免把数据库 dump 和旧备份递归装入对象归档。

## 默认验证与恢复演练

以下命令只解析 manifest、校验全部 SHA-256、验证 PostgreSQL custom dump、检查
归档路径，并逐个下载对象备份计算 SHA-256；不会连接目标数据库或写入主对象存储：

```bash
sudo /opt/mcweb/current/bin/restore \
  --backup /var/backups/mcweb/20260726T120000Z
```

对象存储恢复还必须配置第三个、隔离且为空的目标桶。它不得等于生产源桶或备份桶，
并使用独立的 `MCWEB_RESTORE_S3_*` 变量；以下凭据仍须通过 secret 注入：

```bash
export MCWEB_RESTORE_S3_BUCKET=mcweb-restore-drill-20260726
export MCWEB_RESTORE_S3_REGION=us-east-1
# 非 AWS 兼容服务另设 MCWEB_RESTORE_S3_ENDPOINT 和 FORCE_PATH_STYLE。
```

实际数据库恢复必须连接到新建空库，并同时提交精确数据库名与备份 ID：

```bash
sudo -u postgres createdb mcweb_restore_20260726
sudo env DATABASE_URL='postgresql:///mcweb_restore_20260726' \
  /opt/mcweb/current/bin/restore \
  --backup /var/backups/mcweb/20260726T120000Z \
  --apply \
  --target-database mcweb_restore_20260726 \
  --confirm RESTORE:20260726T120000Z
```

只要目标库已有非系统 schema、表、视图、序列、函数、用户类型、event trigger 或
非默认扩展，连接到的数据库名不同，或确认文本不精确，恢复就会终止。
`pg_restore` 使用单事务；任何后置必要表检查失败时仍应删除并重新创建演练库，
不要在未确认状态的库上重试。

私有对象会在数据库事务开始前写入隔离目标桶。中断后重试会复用内容完全一致的
目标对象；同名但内容不同的目标对象不会被覆盖。对象阶段失败时目标数据库仍为空，
数据库阶段失败时可以删除并重建空库后安全复用已验证对象。旧版
`mcweb-backup-v1` 的私有 S3 清单不含对象本体，脚本只允许校验其旧元数据，拒绝将其
作为完整恢复应用。

本地盘恢复还必须指定一个不存在的绝对目录：

```bash
sudo env DATABASE_URL='postgresql:///mcweb_restore_20260726' \
  /opt/mcweb/current/bin/restore \
  --backup /var/backups/mcweb/20260726T120000Z \
  --apply \
  --target-database mcweb_restore_20260726 \
  --storage-target /var/lib/mcweb-restore/uploads \
  --confirm RESTORE:20260726T120000Z
```

归档不会恢复原始 owner 或危险权限。完成隔离比对后，按目标部署用户显式执行
`chown -R mcweb:mcweb /var/lib/mcweb-restore/uploads`，不得对未确认路径使用递归
改权。

恢复结束后应让隔离应用的 `MCWEB_S3_BUCKET` 指向 `MCWEB_RESTORE_S3_BUCKET`，启动
隔离实例并通过 Active Storage 下载代表性对象。不得让生产应用在演练过程中指向
恢复桶，也不得把恢复目标设为生产源桶。

需要恢复 OpenPGP 配置时，目标文件也必须不存在：

```bash
sudo install -d -m 700 /etc/mcweb-restore
sudo env DATABASE_URL='postgresql:///mcweb_restore_20260726' \
  /opt/mcweb/current/bin/restore \
  --backup /var/backups/mcweb/20260726T120000Z \
  --apply \
  --target-database mcweb_restore_20260726 \
  --restore-config \
  --config-target /etc/mcweb-restore/mcweb.env \
  --confirm RESTORE:20260726T120000Z
```

密钥管理引用方式不能由脚本自动取回 secret；恢复人员必须经平台审批取得该固定
版本并写入新的隔离目标。

`--storage-target` 与 `--config-target` 必须彼此独立、不得嵌套，也不得位于备份目录
内。脚本在最终发布暂存目录或解密配置前会再次确认目标不存在；目标在恢复期间被
其他进程占用时，发布会拒绝覆盖。

每次 verify/apply 都会在 `MCWEB_RECOVERY_EVIDENCE_DIR`（默认备份根目录旁的
`recovery-evidence`）原子写入 `mcweb-recovery-evidence-v1` 报告。报告只含备份 ID、
模式、阶段、结果、对象数量、manifest/SHA256SUMS 摘要和 UTC 时间，不含 endpoint、
bucket URL、DSN、文件名、异常原文或凭据。自动化本地演练必须标记
`MCWEB_RECOVERY_EVIDENCE_CLASS=local_acceptance`；只有 apply 模式并提供精确
`EXTERNAL-RESTORE-DRILL:<backup-id>` 确认时才能标为 `production_drill`。
每次进入正式备份阶段后也会在 `MCWEB_BACKUP_EVIDENCE_DIR`（默认
`<backup-root>/.backup-evidence`）写入 `mcweb-backup-run-evidence-v1` 成功/失败报告；
失败报告只有稳定阶段和错误类别，不复制异常原文。若成功备份无法持久化审计报告，
命令仍返回失败，值班人员必须检查已经发布的恢复点与证据目录后再继续自动流程。

## 调度与保留

安装包提供 `mcweb-backup.service` 和 `mcweb-backup.timer`，默认每天 02:30 执行，带
15 分钟随机延迟与 `Persistent=true`。启用前先确认备份桶、secret 产物方式和保留
策略，然后运行：

```bash
# 既有实例先从当前已验证 release 安装/复核这两个 unit；全新 bin/install 会自动安装。
sudo install -m 644 config/templates/mcweb-backup.service /etc/systemd/system/
sudo install -m 644 config/templates/mcweb-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mcweb-backup.timer
sudo systemctl start mcweb-backup.service
sudo systemctl status mcweb-backup.service
```

`bin/backup-maintenance` 使用 `/run/lock` 非阻塞独占锁，依次创建备份、执行完整
verify-only、再运行保留策略。`MCWEB_BACKUP_RETENTION_DAYS` 默认 30，
`MCWEB_BACKUP_RETENTION_COUNT` 默认 7；只有同时超过天数且不在最新保留代数内的
完整 v2 备份才会清理。未完成目录不会当作恢复点，也会保留供排障。远程删除只读取
校验通过的 inventory，逐个限制在已记录备份键；中断时目录改名为 `.pruning-*`，
下一次会幂等续做，不会执行整桶删除。自定义运行时间应通过 systemd timer drop-in
修改 `OnCalendar` 并执行 `systemctl daemon-reload`，不要复制第二套脚本或并行 cron。
非默认备份、数据或日志路径还必须在同一个 drop-in 中收窄/更新 `ReadWritePaths`，
否则 systemd 沙箱会失败关闭，而不是悄悄写到未授权目录。

## 安全更新

先校验发布包 SHA-256，将其解压到新的 release 目录，不要提前修改 `current`
软链接。候选目录必须包含 vendor bundle、预编译资产及可执行的 `bin/rails`、
`bin/rollback`：

```bash
sudo /opt/mcweb/releases/2026.07.26/bin/update \
  --release /opt/mcweb/releases/2026.07.26 \
  --confirm UPDATE:2026.07.26
```

切流前顺序固定为：

1. 验证当前 Web、Worker 和 `/health/ready`；
2. 对候选 release 执行 bundle、Zeitwerk、数据库/model、迁移状态和资产检查；
3. 执行 Stripe 账户绑定门禁并检查旧版本回滚兼容性；
4. 停止 Web 与 Worker，确认服务已经排空，再次执行 Stripe 账户绑定门禁；
5. 在停写窗口内使用候选版本创建并验证备份；
6. 执行候选 migration；
7. 用新 schema 再次检查候选版本、Stripe 门禁和旧版本回滚入口；
8. 原子切换 `current`，启动 Web/Worker，并在限定时间内等待就绪；
9. 只有新版本就绪后才把旧 release 写入 `previous`。

未绑定 Stripe 账户的实例必须先在旧版本中关闭 Stripe。停服后的第二次门禁用于捕获
第一次检查后完成的在途支付或 Webhook；只要出现财务历史，发布就会在备份和
migration 前停止。身份未就绪的新版本还会对 Stripe Webhook 返回可重试错误，直到
同一账户完成连接测试，避免重试事件抢先创建无法绑定的历史。

更新与回滚共享一个非阻塞发布锁；脚本会在读取 `current`/`previous` 前取得锁。
停服后的普通错误、显式安全拒绝以及可捕获的 `INT`、`TERM`、`HUP` 都通过统一
退出清理恢复当前 release。`SIGKILL`、主机掉电等不可捕获故障仍必须由 systemd
与值班流程处理。

数据库 migration 必须遵守 expand/contract：先增加兼容结构，等旧代码完全退出后
再在后续版本删除旧结构。脚本的旧版本启动检查不能证明全部业务请求都与破坏性
schema 变化兼容。

### 私信修订证据的发布门禁

`20260821090000` 至 `20260821090200` 只完成可兼容的 expand、可重启批量回填和
结构约束；标准 `db:migrate` **不会**安装最终跨表修订触发器。发布必须按以下顺序：

1. 正常执行 `db:migrate`。命名 CHECK 会核对表、名称和定义；已验证约束、
   `VALIDATE` 后中断及 `SET NOT NULL` 后中断均可直接重跑，不能改名绕过错误定义；
2. 部署包含 `Community::Message#record_initial_revision` 双写的新 Web 和 Worker，确认
   所有旧 Web、Worker、控制台和长任务已经退出；
3. 执行 `bin/rails db:community_message_revisions:status`。此时返回 `pending` 是预期，
   但队列持续增长或出现摘要不一致必须先排障；
4. 执行 `bin/rails db:community_message_revisions:finalize`。完整扫描在写锁外按高水位
   运行；写锁内只处理数据库触发器捕获且有硬上限的尾部，并受 `lock_timeout` 与
   `statement_timeout` 保护；
5. 再次执行 `status`，只有明确返回 `finalized` 才能把该发布标记为完成。

最终门禁失败时保留现状并重跑：尾部超限、锁超时、语句超时和进程中断都不会要求
删除证据。不得手工清空 `forum_message_revision_backfill_queue`、删除修订、禁用触发器
或修改摘要来强行通过；先停止异常写入者并检查不匹配记录。第一笔旧进程正文编辑会
自动推进 revision 并进入可靠队列，同一消息在该快照落库前的第二笔旧式编辑会失败，
以避免静默丢历史；最终门禁后，任何未双写对应修订的旧进程插入或正文编辑都会在
事务提交时失败。这类错误表示仍有旧进程未排空，不能通过放宽约束解决。

若必须回退 `20260821090000`，migration 会把原属私信的上传恢复为可清理状态，避免
`expires_at = NULL` 的孤儿对象；既有私信复核权限及角色授权会兼容保留，不应把
部署前已经存在的安全授权误当作本次 migration 所有并删除。向下迁移仍只允许在
隔离恢复/已审批事故流程中执行，不能替代备份恢复。

若 migration 本身失败，`current` 不会切换，但数据库可能已经完成此前的若干
migration。此时必须停止发布，检查迁移状态和当前版本兼容性；需要恢复时使用新
空库和已验证备份，不要未经审查直接执行连续 `db:rollback`。

原生 hostd 的旧 Update 动作没有传候选路径和确认文本，安全脚本会拒绝无参数更新。
在 hostd 适配显式候选 release 合同前，应通过受控命令行执行上述更新。

发布包根目录的 `quick-install.sh` 在已有 `current` 时只是安全更新入口：它把发布包
放入一个全新的 `/opt/mcweb/releases/<version>`（同名目录已存在时拒绝覆盖），然后
使用精确的 `UPDATE:<version>` 确认文本调用候选版本的 `bin/update`。它自身不会
修改 `current`、执行 migration 或重启服务。`--fresh` 只允许在尚无 `current`
指针时使用，不能用来绕开升级门禁。

本地 relay 部署同样先在解压后的候选版本中执行
`scripts/check-stripe-account-binding.rb`，成功后才调用 `quick-install.sh`。候选
Stripe 门禁或安全更新任一步返回非零时，relay 会原样失败退出；不会再直接执行
migration、忽略 migration 错误或在失败后强制重启服务。

## 回滚

默认只检查 `previous` 指向的版本，不切换：

```bash
sudo /opt/mcweb/current/bin/rollback --check
```

也可检查明确目标：

```bash
sudo /opt/mcweb/current/bin/rollback \
  --check --target /opt/mcweb/releases/2026.07.25
```

确认检查通过后才执行代码切回：

```bash
sudo /opt/mcweb/current/bin/rollback \
  --apply \
  --target /opt/mcweb/releases/2026.07.25 \
  --confirm ROLLBACK:2026.07.25
```

若目标 release 无法在当前数据库上启动，回滚会在切流前失败。需要恢复旧 schema
时，不应运行自动 `db:rollback`；应建立新空库并从目标时间点备份恢复，验证后再按
事故变更流程切换数据库连接。

## 上线前必须补做的真实验证

仓库现在提供可重复的真实依赖演练：

```bash
bash scripts/run-production-acceptance.sh
```

它会在唯一临时 Compose project 中构建生产镜像，启动 PostgreSQL 18、Redis 8 和
带临时 TLS 的 S3 兼容存储，随后执行全新建库、migration 基线升级、对象写读、
独立备份桶快照、删除源对象、从备份桶 verify-only、向第三个空桶与空库恢复并再次
下载对象。对象存储不可达、错误确认、
非空目标库和 Redis 不可达必须失败。手动 GitHub Actions 入口是
`.github/workflows/production-acceptance.yml`。

该脚本要求 Docker Compose、PostgreSQL 18 client、OpenSSL、Ruby 和已安装 bundle，
并只允许 `mcweb_acceptance_*` 数据库。当前开发机没有 Docker，因此截至
2026-08-22 尚无本机 MinIO/Compose 真实运行成功记录；静态合同与临时 PostgreSQL 18
测试通过不能替代 workflow 结果。
详细边界见 [`QUALITY_ACCEPTANCE.md`](QUALITY_ACCEPTANCE.md)。

即使上述自动演练通过，也不能代替：

- 在与生产同版本 PostgreSQL 上完成 dump、空库恢复、表数量/关键记录比对并记录
  RPO/RTO；
- 在真实外部对象存储删除/隔离源对象后，从不可变备份恢复到新 bucket，并比对订单
  关联 Blob 与全部对象清单；本地 MinIO 结果只能标记为 `local_acceptance`；
- 在不接触应用主机的恢复环境中，用托管私钥解密配置并完成密钥轮换；
- 在预发布 systemd 主机故障注入 bundle、migration、restart 和 readiness 失败，
  证明切流前失败不改 `current`，切流后失败能返回原 release；
- 独立配置并演练 Redis/Sidekiq 的持久化与恢复；本批脚本不备份 Redis；
- 将备份复制到异地、不可变存储并签名或由平台提供真实性证明。`SHA256SUMS`
  只能检测相对完整性，不能抵抗攻击者同时替换文件与校验清单；
- 在静默写入窗口或一致性快照窗口执行完整灾备。数据库 dump 与逐对象快照仍不是
  同一个分布式事务，必须测量并批准实际 RPO/RTO。
