# McWeb 横向扩展与大型功能开发计划

> 本文件是「多实例化部署」+ 4 个大型功能的统一开发计划。每个工作项由一个独立子代理在隔离的
> git worktree / 分支中开发,互不干扰;完成后由人工评审并合并。

## 背景

McWeb 是 Rails 8.1.3 模块化单体(modular monolith),命名空间模块:`Identity` / `Website`(CMS) /
`Community`(论坛,表前缀 `forum_`) / `Commerce`(商城) / `Minecraft`(联动) / `Administration` /
`Operations`;前端 Vue 3 + Inertia + Vite + Tailwind;数据库 PostgreSQL;后台任务 Active Job。

论坛功能已对齐 XenForo/Discourse(50 个对齐 Wave,1609 测试全绿)。下一步是**架构层面的横向扩展**
与 4 个需要独立周期的大型功能。

## 工作项(共 5 项,各一个子代理)

### ① 多实例化 / 服务拆分(优先,foundational)
**目标**:每个实例只运行选定的模块(如"论坛实例""商城实例""联动实例"),实例间通过内部 API /
消息总线连接,组合为一个完整系统,从而获得更好的性能与弹性扩展。

**首个垂直切片**:
- **配置驱动的模块激活**:通过 ENV / SiteSetting 决定本实例启用哪些模块 —— 只挂载对应模块的路由、
  只运行对应模块的后台任务/订阅/调度。默认"全部启用"(单实例行为不变)。
- **实例间通信**:签名鉴权的 service-to-service 内部 HTTP API(客户端 + 端点),或复用 Active Job 队列
  做跨实例事件;含健康检查/服务发现的最小实现。
- **共享基础设施**:DB、缓存、Job 队列的多实例共享配置说明 + 示例。
- **部署拓扑文档** + 示例(docker-compose / Procfile 多服务)。
- 测试覆盖模块激活逻辑;不破坏现有套件。

### ② 富文本 WYSIWYG 编辑器(TipTap / ProseMirror)
在现有 Markdown 编辑器之外提供所见即所得编辑模式(可切换),输出与现有 Markdown/HTML 管线兼容
(`FormatPostBody` 渲染、`forum/preview`、`forum/uploads`)。保留现有 `MarkdownEditor.vue` 作为回退;
不破坏 @提及/#标签自动补全、图片上传等既有能力。

### ③ 反应类型管理后台(XenForo reaction manager)
把当前基于 `SiteSetting`(`forum.reaction_emojis` / `forum.reaction_scores`)的反应,升级为可后台管理的
`Community::ReactionType` 模型:自定义名称/图标(emoji 或上传图)/分值(可正可负)/排序/启用开关。
后台 CRUD + 前端反应选择器读取该模型;兼容现有 `forum_reactions` 数据与 `ToggleReaction`/加权声望分。

### ④ 邮件回帖(reply-by-email)
用户回复通知邮件即可发帖/回私信。入站邮件解析管道(Action Mailbox 或等价方案)+ 回帖地址 token 映射
(主题/私信 → 用户)+ 安全校验 + 复用 `CreatePost`/`SendMessage`。

### ⑤ 实时通知(ActionCable / WebSocket)
站内通知实时推送(无需刷新)。ActionCable 连接(按 `current_user` 鉴权)+ 通知频道,在
`Notification.notify!` 时广播;前端订阅并实时更新通知红点/列表。

## 全体子代理须遵守的约定

- **隔离开发**:你在自己的 git worktree 的独立分支上工作。完成后**提交但不要 push**;在最终汇报里给出
  分支名、改动文件、已通过的测试、剩余工作。
- **数据库隔离**:5 个代理共享同一个 Postgres 实例。**务必使用唯一的测试数据库名**(如在本 worktree 的
  `config/database.yml`/`config/local.yml` 中把 test 库名改为 `mcweb_test_<你的slug>`,或用 `DATABASE_URL` 覆盖),
  `RAILS_ENV=test bundle exec rails db:create db:migrate` 后再跑测试,避免互相踩库。
- **迁移时间戳**:若新增迁移,使用分配给你的时间戳区段(见各代理任务),避免 version 冲突。
- **Windows 限制**:跑测试必须 `PARALLEL_WORKERS=1`(MRI 在 Windows 不能 fork)。
- **质量门禁**:为新行为写测试;**不得破坏现有 1609 个测试**;用户可见文案补 en + zh(`app/javascript/locales/*.ts`
  与 `config/locales/mcweb.*.yml`);跑 `bundle exec rubocop` 与 `bundle exec brakeman -q`。
- **范围纪律**:只动你这个功能相关的代码;遵循既有模式(`ApplicationService` + `ServiceResult`、Inertia 页面等)。
- **务实交付**:这些都是大型功能。目标是**一个连贯、可运行、有测试的首个垂直切片**(能编译、新行为有通过的测试、
  不破坏现有套件)+ 一段简短设计说明,而不是一次性做完整个功能但留下破损状态。
