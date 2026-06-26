# XenForo 对齐路线图(剩余项)

> 由全面缺口分析(6 领域并行扫描 + 综合)产出,按 价值→工作量 排序。
> 已实现的功能不在此列(头衔阶梯、公告横幅、统计、奖杯积分、管理团队页、首页统计/最新主题/最新发帖/在线管理、postbit、OP 徽章、书签标签、隐藏签名、最高在线纪录、Top/New/被链接通知、prefixes、polls、reactions、solved、warnings、PM、saved search、tags、RSS 等)。

## 快速高价值(small effort)
- [x] **邮箱封禁(Email ban)** — ✅ `Administration::EmailBan` + `CheckEmailBan`(注册拦截)+ `Admin::System::EmailBans` CRUD,带测试。
- [x] **私信加星(Star/Favorite)** — ✅ `starred_at` + `toggle_star` + `Messages/Index.vue` 星标按钮/筛选。
- [x] **侧栏「热门主题」部件** — ✅ 复用 `Topic.top_ranked`,首页 widget。
- [x] **公开会员统计页** — ✅ `Community::ForumStatsController` + `/forum/statistics`(指标 + 发帖最多/获赞最多/最新会员)。
- [x] **主题员工私语** — ✅ 复核发现已完整(`Topics/Show.vue` 版主笔记面板 + 创建表单 + `staff_note` action + 序列化);仅缺单条删除(极小,可选)。缺口分析曾误标。

## 中等价值/工作量(medium)
- [x] **回复我的帖子通知** — ✅ `NotifyPostReply`(parent_post 且作者不同则通知,跳过自回复/已引用),`forum.post_reply` 偏好 + 测试。
- [x] **举报中心:指派 + 批量操作** — ✅ 举报详情页新增「认领」(设 reviewer)+「采纳并隐藏/驳回 该目标全部举报」批量动作(`claim`/`resolve_target`),展示审核人。
- [~] **Alerts vs notifications** — ✅ 通知加 `auto_dismiss` 列 + 按类型分类(反应/关注/被链接/回复/引用/资料墙为「提醒」)+ 通知页「清除全部提醒」动作。待做(可选):查看即自动消除、提醒与通知分区展示。
- [~] **主题工具:复制 + 移动重定向桩** — ✅ **复制已完成**:`Community::CopyTopic`(深拷贝主题+帖子到目标分区,展平引用、不触发通知)+ 主题页复制按钮(复用 move 分区选择器)。待做:移动时留 redirect 桩。
- [x] **附件后台管理** — ✅ `Admin::Forum::AttachmentsController` 列表(全部/孤儿筛选 + 分页)/单删/批量清理孤儿,自定义表格页。
- [x] **帮助中心(Help pages)** — ✅ `Community::HelpArticle`(slug 自动生成)+ 后台 CRUD(`Admin::Forum::HelpArticles`)+ 公开页 `/forum/help`(分类列表 + 文章,Markdown 渲染)+ 导航入口。

## 大型(多会话,需谨慎)
- [x] **用户组 + 副组 + 组权限**(对标 XenForo user groups)——**已完成**:`Community::UserGroup` + `GroupMembership` 模型/迁移;后台 CRUD(名称/颜色/优先级/权限键/主组默认/横幅);`User#permission?` 并入组权限(union,请求级 memoize);注册自动加入默认主组;用户卡/资料页组徽章(颜色/横幅);**后台组编辑页按用户名增删成员**;**会员名录按组筛选**;带测试。可选后续:副组/主组切换 UI。
- [ ] **实时通知(ActionCable)** 与 **Web Push**(共享通知扇出基础)
- [ ] **多引用(Multi-quote)**
- [~] **BBCode + 自定义 BBCode 管理** — ✅ **核心 BBCode 标签已完成**:`FormatPostBody#convert_bbcode` 将 `[b][i][u][s][url][img][quote][spoiler]` 转为 Markdown 等价语法(无标签时 no-op,已验证 strong/em/blockquote/link 正确)。待做:管理员自定义 BBCode(`CustomBbcode` 模型 + 后台)。
- [x] **Spam cleaner** — ✅ `Community::SpamCleaner`(软删该用户全部主题/帖子 + 封禁,事务 + 审计 + 计数,可按记录恢复)+ 后台用户页危险操作按钮(确认弹窗)。
- [x] **计划任务只读视图** — ✅ `Admin::Forum::ScheduledTasks` 读取 `sidekiq_cron.yml` 展示周期任务(无 Redis 依赖)。
- [x] **表情(smilies)替换** — ✅ `Community::Smilie`(缓存,无表情时 no-op)+ 后台 CRUD + `FormatPostBody` 代码块后安全替换(管理员定义后才生效)。
- [ ] **论坛主题样式/皮肤**(镜像 `Website::Theme`)、**Phrases 运行时 i18n**、**论坛页面节点 CMS**、**打字指示器**(依赖实时通知)
