# 质量与自动验收

> 状态：仓库内门禁代码已接入；首批浏览器截图基线和真实 Docker 基础设施成功记录仍待生成
> 最后复核：2026-07-29
> 范围：McWeb CE 共享质量门禁；EE 合并 CE 后可追加 EE 专属页面，不得把 EE 实时功能回写 CE

## 用户文案门禁

`npm run check:user-copy` 扫描业务 Vue 模板和 Ruby 的用户文案出口：

- Vue 模板文本，以及 `title`、`label`、`placeholder`、`aria-label` 等可见属性；
- Ruby 的 flash、render 文本、validation 文本和 `error:` / `message:` 等用户错误出口；
- URL、权限键、路由、MIME、HTTP 方法、UUID、颜色和常见技术产品名不会被当作文案。

门禁把两类例外分开：

1. `config/user-facing-copy-baseline.json` 只保存逐项复核过的非生产例外。每项必须
   标记受约束的类别并说明原因；历史兼容项还必须提供跟踪编号和未来复核日期。
   当前 33 项均不是生产文案债务：32 项来自仅开发模式可访问的演示数据，1 项是
   不应翻译的第三方产品名 `Stripe`。新增命中、失效条目、重复条目、未分类条目或
   到期兼容项都会使 CI 失败。
2. `config/user-facing-copy-allowlist.json` 只用于真实误报。每项必须精确匹配
   `file`、`kind`、`text` 并写至少 8 个字符的复核理由；过期或重复例外会失败。

显式运行 `npm run check:user-copy:update-baseline` 只会生成类别为 `unreviewed`
的候选清单，门禁仍会失败；必须逐项迁移到 I18N，或人工填写允许的类别和具体理由，
不能用它掩盖新业务文案。小范围、紧邻源码的特殊例外也可在上一行使用
`copylint: allow-next-line -- 具体复核理由`。

扫描器覆盖 Vue 模板和已知 Ruby 文案出口，但它不是完整的 JavaScript/Ruby AST
语义分析器。脚本中动态拼接的文案、第三方组件运行时内容，以及资金、权限、审核和
安全场景的语义准确性，仍必须由类型检查、系统 E2E 和人工双语复核共同验收。

## Playwright 系统验收

系统测试位于 `test/e2e/`，默认创建后缀为 `_e2e` 的独立 test 数据库，并拒绝在
其他数据库运行 seed。覆盖：

- 后台指标筛选后保留同一浏览器 document，防止按钮触发整页刷新或重新挂载；
- 英文、简体中文，桌面 1440px 和 Pixel 7 移动视口；
- 空指标状态和注入超长翻译后的横向溢出；
- 键盘焦点可见性、Axe WCAG A/AA（包含颜色对比度）、ARIA 和 Reduce Motion；
- `toHaveScreenshot` 像素差异门禁。

本地运行：

```bash
npm run test:e2e:list
npm run check:e2e-baselines
npm run test:e2e
```

首次基线只能显式生成：

```bash
npm run test:e2e:update
```

生成后逐张检查 `test/e2e/__screenshots__/`，确认无隐私数据、布局错误或错误语言，
再把 PNG 与 `test/e2e/screenshot-manifest.json` 一起提交。缺失或多余图片会失败，
测试结果和 HTML 报告不会进入 Git。

截至 2026-07-29，本轮遵守“全部开发后再做 Chrome 验收”的项目约定，且当前任务
明确不启动 Chrome，所以只完成了测试清单编译；六张初始 PNG 尚未生成。
`.github/workflows/production-acceptance.yml` 的浏览器 job 因此会先在 baseline
门禁失败，不能把它表述为已通过。

## 真实基础设施验收

`bash scripts/run-production-acceptance.sh` 使用唯一 Docker Compose project 和
临时目录，完成生产镜像构建、PostgreSQL 18、Redis 8、HTTPS S3 兼容存储、
全新建库、从既定 migration 基线升级、真实对象写读、备份、verify-only 恢复和
空库恢复。还会注入对象存储不可达、错误确认、非空恢复库和 Redis 不可达，确认
流程失败关闭。

该脚本只允许 `mcweb_acceptance_*` 数据库，并在退出时删除自己创建的 Compose
卷和临时证书。它需要 Docker Compose、PostgreSQL 18 client、OpenSSL、Ruby 和
已安装的 bundle。GitHub Actions 中通过手动
`Production acceptance` workflow 启动，避免把重型镜像构建塞进每个普通 PR。

当前开发机没有 Docker 命令，因此本轮只通过了 shell/YAML/静态合同测试，没有
声称真实容器演练成功。该演练也只验证同一隔离 S3 bucket 中的对象与恢复后数据库
清单一致；生产对象的跨 bucket 不可变快照恢复、systemd 主机切流、密钥托管取回、
异地备份和 RPO/RTO 仍必须在预发布环境完成。
