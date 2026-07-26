# CE 开发文档入口

> 最近复核：2026-07-26
> 本目录只保留当前有效的开发待办、架构约束和实现参考；已完成路线图、旧审计与迁移快照不保留在目录中，需要追溯时使用 Git 历史。

## 版本边界

- CE 与 EE 的管理后台使用相同的 UI 样式和视觉规范，后台改动必须维持两版一致。
- CE 面向普通用户的前台继续使用原有老样式，不跟随 EE 前台重写。
- EE 面向普通用户的前台是独立重写后的新版界面，不能反向套用到 CE。
- 实时论坛、Discord 类频道、频道消息分发和相应实时交互只属于 EE；CE 不得包含或恢复这些能力。
- 通用功能和修复先在 CE 完成，再由 EE 作为下游合并。

## 子代理派发入口

读取本目录全部文档后，按以下顺序派发开发任务：

1. [`code-completion-and-developer-mode-plan.md`](code-completion-and-developer-mode-plan.md)：Developer Mode 与尚未形成闭环的代码总计划，按依赖关系拆分。
2. [`production-readiness-backlog.md`](production-readiness-backlog.md)：论坛、商城、公共后台与生产运维缺口，P0 优先。
3. [`PLUGIN_SYSTEM_ROADMAP.md`](PLUGIN_SYSTEM_ROADMAP.md)：插件平台的活动里程碑与待办。
4. 其余文档是实现约束和现行参考，不应仅因为被读取就自动创建重写任务；开发上述待办时必须遵守它们。

操作或排查已落地的 Developer Mode 前，先读
[`DEVELOPER_MODE.md`](DEVELOPER_MODE.md)。它只描述当前源码已经接线的行为，并把
schema 中尚未实现的模拟项单独列出；不得用活动计划中的目标代替现状。

## 当前文档清单

| 文档 | 角色 | 使用方式 |
|---|---|---|
| [`API.md`](API.md) | 现行 API 参考 | API、认证、权限范围和外部集成任务的契约依据 |
| [`APPS_AND_PLUGINS.md`](APPS_AND_PLUGINS.md) | 现行架构参考 | 区分平台大应用、受信插件和扩展边界；文中的未来方向需先进入活动路线图再开发 |
| [`ATTACHMENT_SECURITY.md`](ATTACHMENT_SECURITY.md) | 现行附件安全参考 | 内容识别、扫描、隔离、配额、清理、下载边界与上线检查 |
| [`code-completion-and-developer-mode-plan.md`](code-completion-and-developer-mode-plan.md) | 活动开发计划 | Developer Mode、代码闭环、阶段依赖与验收门禁 |
| [`COMMUNITY_QUERY_PLAN_OPERATIONS.md`](COMMUNITY_QUERY_PLAN_OPERATIONS.md) | 现行数据库运维参考 | 社区高频查询的 PostgreSQL 计划基线、脱敏复核入口和容量边界 |
| [`DEVELOPER_MODE.md`](DEVELOPER_MODE.md) | 现行运行参考 | 开关、实际绕过与替身、production foundation、验证、重启、风险和明确未实现项 |
| [`PAYMENT_PROVIDER_CONFIGURATION.md`](PAYMENT_PROVIDER_CONFIGURATION.md) | 现行支付运维参考 | Stripe 加密配置、连接测试、Webhook 检查、权限和上线步骤 |
| [`HOSTD.md`](HOSTD.md) | 现行部署参考 | 安装、主机控制台和运维任务的约束 |
| [`minecraft-resource-packs.md`](minecraft-resource-packs.md) | 现行功能参考 | Minecraft 资源包与商城贴图任务的配置依据 |
| [`PLUGIN_MARKETPLACE.md`](PLUGIN_MARKETPLACE.md) | 现行安全与运维参考 | Marketplace 安装、校验和受信代码边界 |
| [`PLUGIN_SDK.md`](PLUGIN_SDK.md) | 现行 SDK 参考 | 插件 API、生命周期和兼容性约束 |
| [`PLUGIN_SYSTEM_ROADMAP.md`](PLUGIN_SYSTEM_ROADMAP.md) | 活动路线图 | 可直接拆分插件系统子任务 |
| [`PRODUCTION_BACKUP_AND_RELEASE.md`](PRODUCTION_BACKUP_AND_RELEASE.md) | 现行生产运维参考 | 安全备份格式、默认验证恢复、release 预检/切流和仍需真实演练的边界 |
| [`production-readiness-backlog.md`](production-readiness-backlog.md) | 活动生产待办 | 可按优先级和模块直接拆分子任务 |
| [`UI_COMPONENT_LIBRARY.md`](UI_COMPONENT_LIBRARY.md) | 现行 UI 规范 | CE 后台与 EE 后台保持相同样式；CE 用户前台保留老样式 |
| [`WEBSITE_CMS.md`](WEBSITE_CMS.md) | 现行 CMS 参考 | Website CMS 架构、数据和管理流程依据 |

## 文档维护规则

1. 新的开发计划必须写明版本范围、优先级、完成条件和最后复核日期。
2. 功能完成后立即从活动待办移除或标记完成；整份路线图完成后删除文档，由 Git 历史保存记录。
3. 时间点审计、一次性迁移记录和旧并行任务说明不得继续留在 `docs/`。
4. “已实现”必须能指向源码、路由、迁移或测试；只有页面或文案不算完成。
5. CE 不得出现 EE 专属频道、WebSocket 客户端、实时业务广播或输入状态功能。
6. 文档中的想法不自动获得开发优先级；只有活动路线图和活动生产待办可以直接派发。
