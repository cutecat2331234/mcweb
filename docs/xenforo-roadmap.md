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
- [x] **Alerts vs notifications** — ✅ 通知加 `auto_dismiss` 列 + 按类型分类 + 通知页「清除全部提醒」动作 + **打开通知页后提醒自动消除**(本次响应仍按未读展示,`update_all` 在 props 计算后执行,仅影响下次加载与铃铛角标)+ 提醒项「Alert」徽章。
- [x] **主题工具:复制 + 移动重定向桩** — ✅ **复制 + 移动重定向桩均完成**:`Community::CopyTopic`(深拷贝)+ 复制按钮;`MoveTopic` 新增 `leave_redirect:`,移动时在原分区留发布态 redirect 桩(唯一 public_id + redirect_to_topic_id + 一条占位首帖),主题页对 redirect 桩显示「已移动 →」横幅并隐藏帖列;move UI 加「留重定向」复选框。
- [x] **附件后台管理** — ✅ `Admin::Forum::AttachmentsController` 列表(全部/孤儿筛选 + 分页)/单删/批量清理孤儿,自定义表格页。
- [x] **帮助中心(Help pages)** — ✅ `Community::HelpArticle`(slug 自动生成)+ 后台 CRUD(`Admin::Forum::HelpArticles`)+ 公开页 `/forum/help`(分类列表 + 文章,Markdown 渲染)+ 导航入口。

## 大型(多会话,需谨慎)
- [x] **用户组 + 副组 + 组权限**(对标 XenForo user groups)——**已完成**:`Community::UserGroup` + `GroupMembership` 模型/迁移;后台 CRUD(名称/颜色/优先级/权限键/主组默认/横幅);`User#permission?` 并入组权限(union,请求级 memoize);注册自动加入默认主组;用户卡/资料页组徽章(颜色/横幅);**后台组编辑页按用户名增删成员**;**会员名录按组筛选**;带测试。✅ **副组/主组切换 UI 已完成**:组编辑页成员行「设为主组」按钮 → `set_primary` action(置该成员此组为主组、清除其全部其他主组)。
- [ ] **实时通知(ActionCable)** 与 **Web Push**(共享通知扇出基础)
- [x] **多引用(Multi-quote)** — ✅ 复核发现已实现(`Topics/Show.vue` `quotePreviews` 数组累积多个引用 + 引用选区 + composer 多引用预览)。缺口分析曾误标。
- [x] **BBCode + 自定义 BBCode 管理** — ✅ **已完成**:核心标签 `[b][i][u][s][url][img][quote][spoiler]` → Markdown(`convert_bbcode`);**自定义 BBCode** `Community::CustomBbcode`(缓存、Markdown 模板 + `{content}`,经 sanitize 安全)+ 后台 CRUD;均无定义时 no-op。
- [x] **Spam cleaner** — ✅ `Community::SpamCleaner`(软删该用户全部主题/帖子 + 封禁,事务 + 审计 + 计数,可按记录恢复)+ 后台用户页危险操作按钮(确认弹窗)。
- [x] **计划任务只读视图** — ✅ `Admin::Forum::ScheduledTasks` 读取 `sidekiq_cron.yml` 展示周期任务(无 Redis 依赖)。
- [x] **表情(smilies)替换** — ✅ `Community::Smilie`(缓存,无表情时 no-op)+ 后台 CRUD + `FormatPostBody` 代码块后安全替换(管理员定义后才生效)。
- [x] **论坛主题样式/皮肤** — ✅ `Community::ForumTheme`(主色/强调色令牌,单默认,缓存)+ 后台 CRUD;激活的默认主题通过 `--primary`/`--accent` CSS 变量合并进 `PortalLayout` 根(无主题时零影响)。
- [ ] **Phrases 运行时 i18n**(DB 覆盖层 + I18n 后端,大件)、**论坛页面节点 CMS**(与帮助中心重叠,可在其上加层级/导航)、**打字指示器**(依赖实时通知)
- [x] **实时通知(ActionCable)** — ✅ `ApplicationCable::Connection`(签名 session cookie 鉴权)+ `Community::NotificationsChannel`(按用户流)+ `Notification.notify!` 广播(rescue 包裹,不阻塞)+ 前端原生 WebSocket 客户端(`useNotificationStream`,无新依赖)+ 顶栏红点实时更新。生产用 `solid_cable`(已在 Gemfile,无需 Redis)。已验证 notify! 正常。
- [x] **打字指示器** — ✅ `Community::ConversationChannel`(参与者鉴权 + ephemeral typing 动作)+ 前端 `useConversationTyping`(原生 WebSocket 收发、节流、过滤自己)+ 私信页「X 正在输入…」。
- [x] **Web Push** — ✅ `web-push` gem + VAPID(`Community::VapidKeys`,存 SiteSetting)+ `Community::PushSubscription` 模型 + `DeliverWebPush` 服务/Job(接入 `notify!`,rescue + DND + 偏好门控,自动清理失效订阅)+ `public/sw.js` service worker + `useWebPush` 客户端 + 偏好页开关。已验证 VAPID 生成 + notify! 正常。
- [x] **论坛页面节点 CMS** — ✅ `Community::ForumPage`(slug 自动生成,缓存导航项)+ 后台 CRUD + 公开页 `/forum/pages/:slug`(Markdown)+ `show_in_nav` 的页面自动进论坛导航(空时无影响)。
- [x] **Phrases 运行时 i18n** — ✅ `Community::PhraseOverride`(DB 覆盖)+ `Mcweb::PhraseBackend`(I18n Chain 首链,30s 进程内缓存,无覆盖时回退)+ 后台 CRUD(搜索/分页)。已验证:普通翻译正常回退、覆盖生效、缺失键不崩。✅ **前端覆盖也已完成**:`ApplicationController` 把当前 locale 的覆盖反扁平化(`forum.top.title` → 嵌套)经 Inertia 共享,`inertia.ts`/`admin.ts` 入口在挂载前 `mergeLocaleMessage` 注入 vue-i18n,使覆盖同样作用于前端 Vue 文案。

> **路线图已全部完成,可选增强项亦全部完成。** 本轮 5 项可选增强(前端 phrases 合并、移动重定向桩、主组切换、实时私信、提醒查看自动消除)经 5 个隔离 worktree 子代理并行实现、零冲突合并,迁移已跑、冒烟全绿。
