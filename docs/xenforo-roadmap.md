# XenForo 对齐路线图(剩余项)

> 由全面缺口分析(6 领域并行扫描 + 综合)产出,按 价值→工作量 排序。
> 已实现的功能不在此列(头衔阶梯、公告横幅、统计、奖杯积分、管理团队页、首页统计/最新主题/最新发帖/在线管理、postbit、OP 徽章、书签标签、隐藏签名、最高在线纪录、Top/New/被链接通知、prefixes、polls、reactions、solved、warnings、PM、saved search、tags、RSS 等)。

## 快速高价值(small effort)
- [ ] **邮箱封禁(Email ban)** — 镜像 `Administration::IpBan`,新增 `Administration::EmailBan`(pattern 支持 `*@domain`、reason、expires_at、active),后台 `Admin::System::EmailBansController` + Vue 页;注册时校验 `EmailBan.match?(email)`。
- [ ] **私信加星(Star/Favorite)** — `forum_conversation_participants` 加 `starred_at`;`conversations#toggle_star` 镜像 mute/archive;序列化 + `Messages/Index.vue` 加星标筛选。
- [ ] **主题员工私语后台 UI** — `Community::TopicStaffNote` 模型已存在,缺 CRUD/UI;镜像用户 StaffNote。
- [ ] **公开会员统计页** — 复用 admin stats + leaderboard 查询,出一个公开 Members 统计页/侧栏部件。
- [ ] **侧栏「热门主题」部件** — 复用 `Topic.top_ranked`,在 `Sections/Index.vue` 加一个 widget。

## 中等价值/工作量(medium)
- [ ] **举报中心:指派 + 批量操作** — `Community::Report` 已有 reviewer/状态;扩展 admin reports 控制器加 assign + bulk_review + 排序,镜像 BulkModerateToolbar。
- [ ] **回复我的帖子通知** — `NotifyPostReply` 服务,`CreatePost` 有 parent_post 且作者不同则通知;接入 NOTIFICATION_TYPES。
- [ ] **Alerts vs notifications** — 通知加 alert/auto_dismiss 标记,瞬时类型(反应/关注)打开即自动已读。
- [ ] **主题工具:复制 + 移动重定向桩** — `CopyTopic` 服务 + 移动时可选 redirect 桩。
- [ ] **附件后台管理** — `Admin::Forum::AttachmentsController` 列表/删除/清理孤儿(复用 `SyncPostAttachments` unlinked scope)。
- [ ] **帮助中心(Help pages)** — `HelpArticle` 模型 + 后台 CRUD + 公开页,复用 `Website::Page` 约定。

## 大型(多会话,需谨慎)
- [ ] **用户组 + 副组 + 组权限**(对标 XenForo user groups,最高价值的大件)
- [ ] **实时通知(ActionCable)** 与 **Web Push**(共享通知扇出基础)
- [ ] **多引用(Multi-quote)**
- [ ] **BBCode + 自定义 BBCode 管理**
- [ ] **Spam cleaner**(按作者批量清理 + 封禁,需 dry-run + 审计)
- [ ] **论坛主题样式/皮肤**(镜像 `Website::Theme`)、**Phrases 运行时 i18n**、**论坛页面节点 CMS**、**表情(smilies)替换**、**打字指示器**、**计划任务只读视图**
