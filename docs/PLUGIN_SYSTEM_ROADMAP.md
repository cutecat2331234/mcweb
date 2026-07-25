# McWeb 插件系统开发路线

状态：执行中（M1：SDK v1.1 稳定化）
适用范围：CE 插件基础设施，以及 EE 基于 CE 的下游扩展
目标：把当前插件 SDK 从“功能较丰富的开发分支”推进为可稳定发布、可升级、可诊断、可扩展的正式平台。

## 1. 信任模型与非目标

McWeb 的插件采用“安装即信任”模型：

- 用户安装插件，即代表用户完全信任插件作者和插件代码。
- 插件与 McWeb 主程序运行在同一个 Rails 进程和权限域中，可以调用被公开的宿主 API。
- `capabilities` 只用于兼容性声明、管理后台展示和审计，不作为安全沙箱或强制授权边界。
- 不为第三方插件市场建设沙箱、恶意代码扫描、发布者签名、信任根、运行时隔离或 capability 强制拦截。

以下完整性保护仍然保留，因为它们用于防止误操作、损坏和不可恢复的升级失败，而不是把插件视为不可信代码：

- ZIP 路径穿越、压缩炸弹、非法文件名和大小限制。
- 安装包 SHA-256 校验与安装后文件健康检查。
- 安装、升级和卸载的事务日志、回滚与隔离目录。
- 只有具备插件管理权限的管理员才能执行安装、升级、启停和卸载。

## 2. 架构原则

1. CE 是上游，EE 是 CE 的真实下游。通用插件基础设施首先进入 CE，EE 通过合并 CE 提交持续继承。
2. CE 与 EE 不在运行时共享代码或目录；EE 专属能力由 EE 下游代码和 EE 专属插件 API 提供。
3. 实时功能只属于 EE。CE 插件 API 不公开 WebSocket、实时广播或频道实时事件。
4. 优先提供稳定、具名、可测试的扩展点，不鼓励插件直接 monkey patch 内部类。
5. 插件通过宿主服务、策略和权限系统完成业务操作，不能绕过核心校验直接写关键业务表。
6. 涉及订单、退款、库存、履约和外部副作用的扩展点必须遵守事务、幂等、锁和 after-commit 规则。
7. 所有公开接口都带版本命名空间，并定义兼容期、弃用流程和升级说明。
8. 扩展加载顺序必须确定且可解释，支持依赖、优先级、`before`、`after` 和冲突声明。
9. 插件的安装、升级、启停和卸载必须可恢复、可诊断，不允许留下无法识别的半完成状态。

## 3. 当前基线

当前开发分支已经具备以下基础：

- 严格 manifest、SemVer 依赖、拓扑排序、重复 ID 与循环依赖检测。
- 同步事件、监听器、过滤器、不可变 DTO/Result、异常隔离和紧急停用。
- 较完整的论坛 v1 API。
- 本地 ZIP 上传，以及安装、升级、启用、停用、卸载流程。
- 安装包边界检查、校验和、步骤执行、收据、日志、隔离和回滚。
- 管理后台插件列表、详情和基础诊断能力。

但该实现尚未达到正式稳定版标准：

- 当前插件代码仍主要位于功能分支，尚未成为已发布的稳定主线能力。
- 宿主 API 集中于论坛，身份、商业、任务、通知、邮件、存储和后台扩展仍不完整。
- 页面、导航、权限、设置、定时任务、翻译和 UI 插槽缺少统一贡献协议。
- 多 Puma/Sidekiq 进程之间没有完整的激活、重载、确认和回滚协调。
- 缺少插件生成器、构建/验证命令、真实示例插件和正式兼容性矩阵。
- 安装后文件健康检查、组合冲突测试和文档一致性仍需完善。
- 服务装饰器已完成并接入首个论坛核心服务；论坛审核与商城退款的并发可靠性修复均已通过回归测试。

## 4. 分阶段实施

### P0：稳定当前插件分支

#### 4.1 完成服务装饰器

- 定义具名服务扩展协议，明确输入、输出和异常语义。
- 将明确允许扩展的核心服务接入统一调用入口。
- 防止核心服务被意外跳过、重复执行、递归调用或执行两次副作用。
- 支持多个插件按确定顺序组成装饰链。
- 对未声明、重复、循环和不兼容装饰器给出可诊断错误。
- 为每个首批接入服务增加单元测试、组合测试和回归测试。
- 文档明确哪些服务可装饰，哪些只能监听 after-commit 事件。

验收标准：

- 单插件、双插件、异常插件、禁用插件和顺序冲突均有自动化测试。
- 核心策略、权限、事务和幂等校验无法被装饰器静默绕过。
- 管理后台能够看到服务装饰链及其来源。

#### 4.2 消除文档漂移

- 统一 `PLUGIN_SDK.md`、`PLUGIN_MARKETPLACE.md` 与 `APPS_AND_PLUGINS.md` 的现状描述。
- 对已实现、实验性、计划中和 EE 专属能力使用明确标记。
- 增加 SDK 合同矩阵：API 名称、版本、稳定级别、CE/EE 可用性和弃用状态。

#### 4.3 固化 v1 行为

- 为 manifest、依赖解析、生命周期、事件、过滤器、论坛 API 和安装流程建立合同测试。
- 将隐含行为转化为公开契约，不依赖内部实现细节。
- 建立向后兼容测试夹具，确保后续版本仍能加载旧插件。

### P1：扩展稳定宿主 API

#### 4.4 Identity API

- 用户只读查询、受控更新和状态检查。
- 全局身份组查询、成员关系和权限判定。
- 细粒度权限检查与原因返回。
- 通知、私信或站内消息的受控发送入口。
- 隐私、封禁、可见性和管理员策略统一复用核心服务。

#### 4.5 Commerce API

- 商品、分类、价格、库存和可售状态查询。
- 订单读取、状态迁移、履约、取消和退款请求。
- 支付、退款、库存和履约领域事件。
- 插件可注册履约处理器或外部供应商适配器。
- 所有写操作通过核心服务，要求幂等键、事务边界和明确错误类型。
- 外部通知和事件广播只能在事务提交后发生。

#### 4.6 Jobs、通知、邮件、Webhook 与存储

- 版本化后台任务注册与调度入口。
- 统一通知和邮件发送 API，复用模板、语言和退订策略。
- Webhook 发送器提供重试、签名、超时和诊断，但不把插件本身视为不可信。
- 插件命名空间存储、文件附件和临时文件 API。
- 插件停用或卸载后，任务必须可识别、可取消，不产生孤儿任务。

#### 4.7 插件设置

- 插件通过 schema 声明设置项、默认值、校验、敏感显示方式和分组。
- 管理后台根据 schema 生成 Arco Design 表单。
- 配置变更产生版本化事件，并支持回滚到上一个有效版本。
- 插件只能写入自身命名空间，宿主配置通过专门 API 修改。

验收标准：

- 每个 API 都有 DTO、错误协议、权限说明、版本说明和合同测试。
- 所有关键写路径都有事务、并发与幂等测试。
- CE API 中不存在实时 WebSocket 能力。

### P2：统一贡献注册表

实现一个确定性的 contribution registry，插件可声明：

- 权限定义、权限分组和默认权限建议。
- 设置项、设置分组和配置页。
- 定时任务、队列任务和清理任务。
- 公共端与管理端导航项。
- 公共页面、管理页面和受控路由。
- 仪表盘卡片、列表操作、详情页操作和表单字段插槽。
- I18N phrase 命名空间、语言包和回退规则。
- 预编译前端资源、图标和 UI 插槽。
- 领域事件目录和插件自定义事件。
- 模型或实体元数据扩展，以及明确允许的稳定扩展点。

注册表规则：

- 同一贡献类型具有稳定排序和来源追踪。
- 支持依赖、优先级、`before`、`after`、互斥和冲突声明。
- 安装时验证贡献，启用时原子激活，停用时原子撤销。
- 卸载时能够区分插件拥有的数据、共享数据和宿主数据。
- 管理后台可查看某插件注册的全部权限、页面、任务、翻译、服务扩展和事件。
- 冲突信息必须包含插件 ID、贡献 ID、解析顺序和可执行的修复建议。

前端约束：

- 管理端扩展 UI 使用项目统一的 Arco Design 组件和设计令牌。
- 优先使用预定义插槽和 schema 驱动表单，避免插件依赖宿主 DOM 结构。
- 是否允许插件提供预编译 ESM 前端模块，在 P4 前完成正式决策。

### P3：生命周期与多进程一致性

#### 4.8 持久化状态机

插件生命周期至少包含：

`uploaded → validated → staged → installing → installed → enabling → enabled`

以及：

`disabling → disabled`、`upgrading`、`uninstalling`、`failed`、`quarantined`、`rolling_back`

要求：

- 每次转换记录操作者、时间、版本、generation、步骤和错误。
- 每个步骤可安全重试，或明确标记为不可重试并自动回滚。
- 禁止多个管理员并发操作同一插件。
- 支持 dry-run、维护模式、失败恢复和手工确认恢复点。

#### 4.9 多进程协调

- 数据库保存期望的插件 generation 和启用集合。
- Puma、Sidekiq 等每个进程加载后回报 generation 与健康状态。
- 启停或升级时通知全部进程重载，并等待规定比例确认。
- 超时、部分失败或新版本启动失败时自动回滚到上一 generation。
- 新启动的进程必须先读取持久化状态，不能依赖旧进程内存。
- 管理后台展示每个进程的版本、generation、最后确认和失败原因。

#### 4.10 文件健康检查

- 构建时生成插件文件清单和哈希。
- 安装后、启动时和管理员手工检查时可检测缺失、修改和未知文件。
- 文件异常用于运维诊断，不作为发布者信任判断。
- 修复流程支持重新安装同版本或回滚到已知良好版本。

验收标准：

- 至少用两个 Web 进程和一个 Job 进程完成启停、升级、失败回滚测试。
- 在任一进程重载失败时，系统不会长期处于混合版本且无告警。
- 断电式中断生命周期步骤后可以恢复或回滚。

### P4：开发者工具与参考插件

#### 4.11 CLI 与生成器

提供以下标准命令：

- `plugin:create`：生成 manifest、目录结构、入口类、测试和语言文件。
- `plugin:validate`：校验 manifest、依赖、贡献、API 版本和文件清单。
- `plugin:test`：运行插件合同测试和宿主兼容测试。
- `plugin:build`：输出可安装 ZIP、文件清单和校验和。
- `plugin:release`：生成版本变更记录和发布产物。
- `plugin:health`：检查已安装文件和运行时注册状态。

开发体验：

- 开发环境可控热重载，不影响生产语义。
- 提供插件测试基类、工厂、模拟宿主 API 和事件断言。
- 提供兼容性矩阵检查和弃用警告。
- 所有命令有 JSON 输出模式，便于 CI 使用。

#### 4.12 参考插件

至少维护三个真实、可安装、可测试的参考插件：

1. Hello/Event：演示 manifest、设置、事件、翻译和管理页。
2. Forum Extension：演示自定义字段、审核动作、权限和 UI 插槽。
3. Commerce Fulfillment：演示订单事件、幂等履约、失败重试和 after-commit。

EE 另维护一个独立参考插件，演示 EE 专属实时事件与频道能力；该代码不进入 CE。

验收标准：

- 新开发者只参考文档即可创建、测试、构建、安装和升级插件。
- 三个参考插件在 CI 中执行完整生命周期测试。
- CE 构建与测试不依赖 EE 仓库或 EE 运行时。

### P5：管理后台与生态体验

- 重构插件详情页，统一使用 Arco Design。
- 展示版本、作者、依赖、冲突、兼容范围、启用状态和进程一致性。
- 展示插件拥有的权限、设置、页面、路由、任务、事件、翻译、资源和服务装饰器。
- 提供配置表单、生命周期历史、诊断日志、健康检查和恢复入口。
- 安装和升级前展示依赖变化、贡献变化、数据库步骤与影响摘要。
- 明确区分“兼容性警告”“运行错误”“文件损坏”和“需要重启”。
- 插件市场仅负责发现与获取；安装动作即代表用户信任，不增加发布者安全审核体系。

验收标准：

- 常见管理操作无需查看服务器日志即可定位失败阶段。
- 所有破坏性动作有明确目标、影响摘要和可恢复说明。
- 不使用散落的自写 CSS 修补布局；必要样式集中在设计令牌和少量作用域样式中。

### P6：正式发布与长期兼容

- 发布 SDK 版本策略、兼容窗口和弃用时间线。
- 为每次宿主版本发布兼容性矩阵和插件升级指南。
- 建立插件 API changelog，并区分新增、弃用和破坏性变更。
- 对上一稳定 SDK 运行完整合同测试。
- 为 CE 到 EE 的合并建立固定检查，确保 EE 提交历史真实包含对应 CE 基线。
- 正式发布前冻结接口，完成升级、降级、回滚、组合冲突和多进程测试。

## 5. 可直接派发的并行工作包

主线程最多同时保留三个子代理，加主代理负责集成。每个代理必须先检查工作区现有未提交改动，不得覆盖其他任务。

### 工作包 A：运行时与生命周期

负责范围：

- `lib/mcweb/plugins/**`
- 插件生命周期与 marketplace 后端
- 对应 runtime、registry、loader、lifecycle 测试

首批任务：

1. 完成服务装饰器协议和调用链。
2. 建立 SDK 合同测试。
3. 设计并实现持久化 generation。
4. 完成多进程 reload/ack/rollback。
5. 增加安装后文件健康检查。

禁止修改：

- Identity、Commerce 业务服务实现。
- 管理后台视觉组件。
- 其他代理负责的文档章节，除非先协调。

### 工作包 B：Identity、Site 与基础能力 API

负责范围：

- `app/services/plugin_api/v1/identity/**`
- `app/services/plugin_api/v1/site/**`
- Jobs、通知、邮件、Webhook、存储和设置 API
- 对应 DTO、合同测试和 API 文档

首批任务：

1. 建立 Identity API 与全局身份组权限查询。
2. 建立插件设置 schema。
3. 建立 Jobs、通知和邮件 API。
4. 建立插件命名空间存储。
5. 保证 CE 不出现任何实时 WebSocket API。

禁止修改：

- 插件 registry 核心实现。
- Commerce 领域服务。

### 工作包 C：Commerce API

负责范围：

- `app/services/plugin_api/v1/commerce/**`
- 必要的 Commerce 领域服务适配
- 订单、库存、退款、履约事件与测试

首批任务：

1. 设计 Commerce DTO 与错误协议。
2. 接入商品、订单、库存、退款和履约服务。
3. 加入幂等键、事务和并发测试。
4. 保证副作用仅在 after-commit 后触发。
5. 编写 Commerce Fulfillment 参考插件。

禁止修改：

- 通用 registry 和 loader。
- 无关 Commerce 业务规则。

### 工作包 D：贡献注册表、后台 UI 与开发者体验

负责范围：

- 插件 contribution registry 的上层协议与适配
- 管理后台控制器、路由、页面和 Arco Design 组件
- CLI/生成器、参考插件与公开文档

首批任务：

1. 定义权限、设置、导航、页面、任务、翻译和 UI 插槽贡献协议。
2. 实现插件详情、配置、诊断和生命周期历史页面。
3. 实现 create/validate/test/build/health 命令。
4. 建立 Hello/Event 与 Forum Extension 参考插件。
5. 修正文档漂移并维护合同矩阵。

禁止修改：

- 核心 Commerce 业务服务。
- 底层 registry 数据结构；需要调整时先提交接口需求给工作包 A。

### 工作包 E：集成、冲突测试与发布门禁

该工作包由主代理执行，避免多个代理同时修改集成文件。

负责内容：

- 合并各工作包并解决接口差异。
- 运行单测、集成测试、系统测试和静态检查。
- 设计多插件组合、顺序、冲突和故障注入测试。
- 验证参考插件的安装、启停、升级、回滚和卸载。
- 核对文档与实际行为。
- 核对 CE → EE 的 Git 下游关系。
- 将发现的缺陷分派回唯一文件所有者。

## 6. 里程碑

### M1：SDK v1.1 稳定化

- 服务装饰器完成并接入首批核心服务。
- 文档与实现一致。
- 现有 manifest、事件、论坛 API 和生命周期合同冻结。
- 当前插件测试全部通过。

### M2：通用平台 API

- Identity、全局身份组、Commerce、Jobs、通知、邮件、存储和设置 API 可用。
- 贡献注册表覆盖权限、导航、页面、任务、翻译和 UI 插槽。
- 关键写路径通过事务、幂等和并发测试。

### M3：生产级生命周期

- 多进程 generation 协调可用。
- 启停、升级和回滚不会产生长期混合状态。
- 文件健康检查、故障恢复和诊断页面完成。

### M4：开发者生态

- CLI、生成器、测试工具和三个 CE 参考插件完成。
- EE 实时参考插件仅存在于 EE。
- 兼容性矩阵、弃用策略、升级指南和发布流程完成。

## 7. 缺陷处理规则

- 开发过程中发现的缺陷直接在所属工作包内修复，不另行等待。
- 每个修复必须附带能够复现问题的回归测试。
- 涉及订单、退款、权限、安装状态或数据删除的缺陷，必须同时验证失败路径和恢复路径。
- 若缺陷跨越文件所有权，由主代理指定唯一修复负责人，其他代理只提供证据，不并行修改同一实现。
- 纯设计选择、数据迁移风险或会改变公开契约的问题不得静默决定，应记录到决策日志后由主代理确认。

## 8. 暂不阻塞开发的设计决策

以下问题可以并行调研，但必须在对应里程碑冻结前确定：

1. 前端插件只使用宿主预定义 UI 插槽，还是允许上传预编译 ESM 模块。
2. 卸载插件时，插件拥有的数据默认保留、删除，还是每次要求管理员选择。
3. 新增 Identity/Commerce 等命名空间继续归入 v1，还是在稳定发布前统一提升为 v2。
4. 插件数据库迁移采用独立版本表，还是复用宿主迁移框架并增加插件命名空间。

## 9. 完成定义

只有同时满足以下条件，插件系统才可称为“足够完善”：

- 工作区无意外改动，所有改动归属清晰。
- 单元、集成、系统、组合冲突和故障恢复测试全部通过。
- 至少三个真实参考插件完成端到端安装、配置、启停、升级、回滚和卸载。
- 多进程环境下不存在长期 generation 不一致。
- 插件不能绕过核心权限、事务、幂等和策略校验。
- 管理后台可诊断依赖、冲突、文件健康、生命周期和进程加载问题。
- 文档、合同矩阵和实际实现一致。
- CE 不包含实时功能；EE 专属实时 API 和参考插件只存在于 EE。
- EE 的 Git 历史真实继承对应 CE 基线，没有复制代码造成的伪下游关系。
- 已明确记录安装即完全信任，且没有投入沙箱、签名、恶意扫描或 capability 强制隔离。

## 10. 目标架构

### 10.1 分层结构

插件平台最终拆分为六层，各层只能依赖其下方的稳定合同：

1. **包与清单层**
   - 负责 ZIP、manifest、文件清单、版本、依赖和 edition 校验。
   - 不加载插件 Ruby 代码，不执行业务逻辑。
2. **生命周期层**
   - 负责安装、升级、启停、卸载、回滚、generation 和进程确认。
   - 所有状态变化持久化，并产生可审计的 lifecycle run。
3. **运行时注册层**
   - 负责入口类、事件、过滤器、服务装饰器和 contributions。
   - 对外提供不可变的运行时快照，避免加载过程中暴露半成品 registry。
4. **Host API 层**
   - 负责论坛、身份、商业、任务、通知、邮件、存储和站点配置。
   - 只返回公开 DTO/Result，不向插件承诺 ActiveRecord 内部对象稳定性。
5. **贡献与展示层**
   - 负责权限、设置、导航、页面、任务、翻译、资源和 UI 插槽。
   - 管理端统一由 Arco Design 渲染。
6. **开发工具层**
   - 负责生成、验证、测试、构建、发布、健康检查和兼容性报告。

### 10.2 安装数据流

1. 管理员上传本地包或从市场选择版本。
2. 系统只读取包结构并执行静态校验。
3. 生成 canonical manifest、package digest 和文件清单。
4. 解析依赖、宿主版本、edition 和已安装插件冲突。
5. 创建 staged release，不立即改变当前运行时。
6. 执行 setup/migration steps，并持续写入 lifecycle journal。
7. 构建新的不可变 registry snapshot。
8. 切换 desired generation，要求各运行进程加载并确认。
9. 达到确认门槛后提交 active generation。
10. 任一步骤失败时，撤销 staged release 或恢复上一 generation。

### 10.3 运行时调用流

```text
Controller / Job / Domain Command
            |
            v
     Core Policy & Validation
            |
            v
   Versioned Host Service API
            |
            +--> Service Decorator Chain
            |
            v
      Core Domain Service
            |
            v
       Database Commit
            |
            +--> After-commit Domain Events
            +--> Notifications / Jobs / Webhooks
            +--> EE-only Realtime Adapter
```

约束：

- pre-validation filter 只能调整允许调整的输入，不能提交外部副作用。
- service decorator 必须通过 `proceed` 明确继续核心链路；continuation 由框架保证下游操作最多执行一次。
- 依赖已提交业务状态的邮件、Webhook、队列任务和 EE 实时广播必须从 after-commit event 或可靠 outbox 触发。
- “不能绕过核心策略”是官方 SDK 的合同要求，不是安全沙箱承诺；受信任插件仍与宿主处于同一进程。

### 10.4 建议的持久化实体

名称可随现有 Rails 命名约定调整，但职责必须保持分离：

- `plugin_installations`
  - 插件 ID、当前版本、期望状态、当前状态、edition 和错误摘要。
- `plugin_releases`
  - 每个已上传版本的 manifest digest、package digest、路径和兼容状态。
- `plugin_lifecycle_runs`
  - 一次安装、升级、启停、卸载或恢复操作。
- `plugin_lifecycle_steps`
  - 步骤序号、幂等键、开始/结束时间、结果和回滚信息。
- `plugin_generations`
  - registry snapshot、期望 generation、激活时间和上一稳定 generation。
- `plugin_process_acks`
  - 进程 ID、类型、加载版本、generation、健康状态和最后心跳。
- `plugin_contributions`
  - 贡献类型、贡献 ID、来源插件、顺序、状态和 schema digest。
- `plugin_settings`
  - 插件命名空间、设置键、值、版本和最后修改者。
- `plugin_file_records`
  - 相对路径、大小、摘要和健康状态。

数据库只保存可重建的注册元数据；实际 Ruby 类和前端产物仍来自已安装 release。

## 11. Manifest 与包格式合同

### 11.1 建议字段

```yaml
schema_version: 1
id: example.fulfillment
name: Example Fulfillment
version: 1.2.0
edition:
  - ce
  - ee
host:
  mcweb: ">= 1.8 < 2.0"
  ruby: ">= 3.3"
entrypoint: Example::Fulfillment::Plugin
dependencies:
  mcweb.base_payments: ">= 2.1 < 3.0"
conflicts:
  - plugin: legacy.fulfillment
    reason: registers the same fulfillment provider
capabilities:
  - commerce.orders.read
  - commerce.fulfillment.write
contributions:
  permissions: config/permissions.yml
  settings: config/settings.yml
  events: config/events.yml
  navigation: config/navigation.yml
  jobs: config/jobs.yml
  ui_slots: config/ui_slots.yml
i18n:
  path: locales
assets:
  manifest: assets/manifest.json
setup:
  install: Example::Fulfillment::Setup
  upgrade: Example::Fulfillment::Setup
  uninstall: Example::Fulfillment::Setup
files:
  manifest: files.sha256
```

### 11.2 校验规则

- 插件 ID 使用稳定的反向域名式或组织前缀命名，安装后不得更改。
- `schema_version` 与插件 `version` 独立演进。
- 所有路径必须是包内相对路径，规范化后仍位于包根目录。
- entrypoint 必须存在，并符合允许的常量命名规则。
- dependency range 必须可解析，禁止隐含的“最新版本”。
- EE-only 插件必须声明 `edition: [ee]`；CE 在执行任何插件代码前拒绝加载。
- manifest 未声明的 contribution 不自动注册。
- `capabilities` 不决定安全权限，只生成兼容性与审计报告。
- canonical manifest 使用固定字段顺序和编码，以便生成稳定 digest。
- 未识别字段默认报错；需要前向兼容的扩展字段统一放入 `extensions` 命名空间。

### 11.3 包内目录

```text
plugin.yml
files.sha256
lib/
app/
config/
locales/
assets/
db/
test/
README.md
CHANGELOG.md
```

要求：

- 运行时代码、配置、迁移、语言和前端资源彼此分离。
- 构建产物不包含开发缓存、私钥、本机配置、日志和测试数据库。
- 是否打包 `test/` 可配置；官方参考插件默认保留合同测试。
- 包格式必须可复现构建：同一提交与同一工具版本产生相同文件顺序和摘要。

## 12. Host API 统一合同

### 12.1 DTO 与结果类型

- 对外只暴露不可变 DTO、值对象和分页对象。
- ID 使用明确类型或带资源前缀的字符串，避免不同领域 ID 混用。
- 时间统一包含时区，序列化为 ISO 8601。
- 金额由币种和最小货币单位组成，不使用浮点数。
- 可空字段、缺失字段和不可见字段具有不同语义。
- 写操作返回统一 `Result`，至少包含：
  - `ok?`
  - 稳定错误码
  - 本地化消息键
  - 字段错误
  - 可重试标记
  - correlation ID
- 不把 Rails exception、SQL 文本或内部模型直接作为公共合同。

### 12.2 调用上下文

每次 Host API 调用携带统一 context：

- 调用插件 ID 与版本。
- 当前用户、系统任务或匿名主体。
- locale、时区与请求 ID。
- 当前事务状态。
- 幂等键与调用来源。
- edition 和宿主 API 版本。

context 用于审计和正确性，不用于把可信插件隔离成不可信进程。

### 12.3 版本与弃用

- 路径和 Ruby 命名空间都包含 API 主版本。
- 同一主版本只做向后兼容新增。
- 弃用至少经过一个稳定宿主版本，并在开发、测试环境输出一次性警告。
- 删除接口前提供迁移示例、替代 API 和自动检测规则。
- `plugin:validate` 能根据目标宿主版本报告已弃用或缺失接口。

### 12.4 查询规范

- 列表查询统一使用 cursor pagination。
- 过滤、排序和 include 列表采用白名单。
- 默认限制返回数量，避免插件意外加载全表。
- 权限过滤由宿主完成，插件无需复制可见性规则。
- 批量查询优先，避免插件循环调用产生 N+1。

## 13. 扩展点与事件语义

### 13.1 扩展点分类

| 类型 | 执行时机 | 是否允许修改结果 | 是否允许外部副作用 | 失败语义 |
| --- | --- | --- | --- | --- |
| Validator | 核心命令校验阶段 | 只能增加校验错误 | 否 | 阻止命令 |
| Filter | 明确的输入/展示转换点 | 是 | 否 | 使用原值或阻止，按合同定义 |
| Service decorator | 核心服务调用期间 | 是 | 仅按服务合同 | 插件异常诊断隔离并回退链路；核心异常原样传播 |
| Domain event | 数据库提交后 | 否 | 是 | 记录并按策略重试 |
| Lifecycle hook | 插件生命周期期间 | 仅自身步骤 | 受 journal 管理 | 失败或回滚 |
| UI contribution | registry 构建时 | 注册声明 | 否 | 禁用该贡献或阻止启用 |

### 13.2 事件命名

- 宿主事件使用 `mcweb.<domain>.<resource>.<action>.v<major>`。
- 插件自定义事件使用 `plugin.<plugin_id>.<event>.v<major>`。
- 事件名称、payload schema、事务语义和投递语义都进入事件目录。
- 事件 payload 只包含稳定 DTO 或 ID，不包含 ActiveRecord 实例。

示例：

- `mcweb.forum.topic.created.v1`
- `mcweb.identity.group_membership.changed.v1`
- `mcweb.commerce.order.paid.v1`
- `mcweb.commerce.refund.completed.v1`
- EE-only：`mcweb.ee.channel.message.created.v1`

### 13.3 投递保证

- 进程内 filter 和 decorator 是同步调用，最多执行一次。
- after-commit domain event 默认至少投递一次，消费者必须支持幂等。
- 需要可靠投递的事件采用持久化 outbox，再由任务队列分发。
- 重试采用有限次数和退避策略，最终失败进入可查看的 dead-letter 状态。
- 插件停用后，尚未执行的插件专属任务默认暂停，不静默丢弃。
- 插件升级时，旧任务 payload 必须由兼容处理器读取，或提供显式迁移。

### 13.4 顺序与冲突

- 默认顺序首先按依赖拓扑，再按优先级，最后按稳定插件 ID 排序。
- `before`/`after` 只能引用同类 contribution。
- 循环顺序依赖直接阻止插件启用。
- 多个 filter/decorator 的最终顺序在后台可视化。
- 同一插件升级后顺序变化必须出现在影响摘要中。

## 14. 身份组与插件权限

### 14.1 权限命名

- 插件权限使用 `<plugin_id>.<resource>.<action>`。
- 宿主保留 `mcweb.*` 命名空间。
- 权限必须声明标题 phrase、说明 phrase、分组、适用范围和默认建议。
- 默认建议只用于安装向导，不自动授予任何高权限操作。

示例：

```yaml
permissions:
  - id: example.fulfillment.order.view
    group: example.fulfillment.orders
    title_phrase: permission.order_view.title
    description_phrase: permission.order_view.description
    scope: global
    default: none
```

### 14.2 全局身份组集成

- 插件可查询用户所属的全局身份组和最终权限结果。
- 插件不能另建一套与宿主冲突的成员角色体系。
- 权限解析结果包含 allow/deny、来源身份组和必要的范围信息。
- 身份组变更后使相关权限缓存失效。
- 身份组删除、重命名或合并时，插件配置引用必须可迁移并给出诊断。
- EE 的频道级覆盖权限建立在全局身份组之上，但频道实时功能不得进入 CE。

### 14.3 插件管理权限

宿主至少提供：

- 查看插件。
- 安装插件。
- 升级插件。
- 启用/停用插件。
- 修改插件配置。
- 查看插件诊断与日志。
- 执行恢复或回滚。
- 卸载但保留数据。
- 卸载并清除数据。

这些权限控制管理员操作范围，不改变“插件代码本身被完全信任”的运行模型。

### 14.4 权限生命周期

- 安装时注册权限定义，但不隐式授予。
- 升级时允许新增、弃用和迁移权限。
- 停用时保留身份组授权，重新启用后恢复。
- 卸载保留数据时一并保留授权快照。
- 清除数据时删除插件权限定义和授权，但必须出现在影响摘要中。

## 15. 数据、迁移与卸载

### 15.1 数据所有权

数据分三类：

1. **插件独占数据**
   - 插件创建的表、设置、任务、文件和缓存。
2. **宿主扩展数据**
   - 通过受控 metadata/custom-field API 附加到宿主资源的数据。
3. **宿主核心数据**
   - 用户、帖子、订单、支付和权限等核心记录。

卸载操作只能自动删除第一类；第二类按贡献协议清理；第三类不得由通用卸载器直接级联删除。

### 15.2 数据库约定

- 插件表使用稳定命名空间或前缀。
- 每个插件维护独立 migration version。
- migration step 必须有稳定 ID 和幂等检查。
- 长时间迁移支持分批、断点和进度报告。
- 表结构变更与代码 generation 切换分阶段执行，兼容滚动部署。
- destructive migration 必须先经过兼容版本和数据备份门禁。
- 插件不得通过官方 SDK 直接修改核心表结构；需要宿主扩展点时先增加 metadata API。

### 15.3 升级协议

1. 静态校验新版本。
2. 校验从当前版本到目标版本存在升级路径。
3. 执行向前兼容的 prepare migration。
4. 构建并验证新 registry。
5. 切换 generation。
6. 完成 finalize migration 和旧资源清理。
7. 在恢复窗口内保留上一 release。

### 15.4 卸载模式

- **停用**：停止代码和贡献，保留版本、配置与数据。
- **卸载并保留数据**：移除代码和运行时贡献，保留插件数据与恢复元数据。
- **卸载并清除数据**：执行受 journal 管理的 purge，管理员确认影响摘要。

默认模式在正式发布前确定；在未确定前，产品界面不得使用含糊的单一“卸载”按钮。

## 16. 前端与 Arco Design 扩展规范

### 16.1 支持的贡献方式

优先级从稳定到灵活：

1. schema 驱动的设置表单、列表、详情卡片和操作按钮。
2. 宿主提供的具名 UI slot。
3. 预编译、版本化的前端模块。

能由前两种表达的功能不得要求插件操作宿主 DOM。

### 16.2 Arco 组件映射

| 场景 | 首选组件 |
| --- | --- |
| 插件状态 | Tag、Badge、Status |
| 依赖与贡献概览 | Descriptions、Collapse |
| 生命周期历史 | Timeline、Steps |
| 设置 | Form、Input、Select、Switch、InputNumber |
| 权限矩阵 | Table、Checkbox、Tree |
| 诊断与错误 | Alert、Result、Drawer |
| 危险操作确认 | Modal、Popconfirm |
| 大型贡献目录 | Tabs、Table、Pagination |
| 进程 generation 状态 | Statistic、Progress、Table |
| 版本与升级摘要 | Card、Typography、Diff 风格列表 |

设计约束：

- 圆角卡片与方形数据表按层级混合使用，不全站统一成一种形状。
- 页面容器、栅格、间距、字号和密度使用统一 design tokens。
- 表格不嵌套过深；详细诊断放入 Drawer。
- 状态颜色具有文字和图标辅助，不能只依赖颜色。
- 小屏幕下设置表单、权限矩阵和详情区必须可用。
- 自写 CSS 只处理 Arco 无法表达的必要布局，并使用插件作用域。

### 16.3 前端模块合同

若最终允许预编译 ESM：

- 模块只通过版本化 frontend SDK 获取路由、I18N、主题和 Host API。
- 禁止依赖宿主内部组件文件路径。
- 每个模块声明前端 SDK 范围和 Arco 兼容版本。
- CSS 使用插件根作用域，禁止全局 reset。
- 模块加载失败只禁用对应 UI contribution，不应使整个管理后台白屏。
- 插件升级后前端资源使用 content hash，避免旧缓存与新后端混用。

### 16.4 I18N

- phrase 键使用 `<plugin_id>.<area>.<name>`。
- manifest、权限、设置、菜单、错误和按钮不得直接硬编码用户可见文本。
- 默认语言缺失直接阻止构建。
- 其他语言缺失回退默认语言，并在后台生成覆盖率报告。
- 插值变量在 schema 中声明，运行时检查缺失变量。
- 支持复数、日期、货币和时区格式，不由插件手工拼接。

## 17. 可观测性与运维

### 17.1 结构化日志

每条插件相关日志至少包含：

- plugin ID 与版本。
- generation。
- lifecycle run 或 event delivery ID。
- request/correlation ID。
- contribution、event 或 service 名称。
- 执行耗时和结果。
- 重试次数与最终状态。

默认不记录密码、token、支付凭据、私信正文和其他敏感内容。

### 17.2 指标

- registry 构建次数、耗时和失败数。
- 插件加载、重载和 generation 确认耗时。
- 各插件 hook 调用数、错误率和延迟分布。
- 事件 outbox 积压、重试和 dead-letter 数量。
- 插件任务队列深度和最老任务年龄。
- 生命周期步骤成功、失败、回滚次数。
- 文件健康异常数。

### 17.3 健康状态

单插件健康状态由以下维度组成：

- 包与文件完整性。
- 依赖和版本兼容。
- registry 注册。
- 数据库 migration 版本。
- 后台任务处理器。
- 各进程 generation 一致性。
- 最近生命周期操作。
- 最近事件和服务错误。

后台显示综合状态，但每个维度必须可展开，不能只给出“异常”。

### 17.4 初始性能预算

以下为首轮工程预算，基准测试后可调整：

- 无插件时，运行时调用包装开销应接近可忽略，不引入额外数据库查询。
- 无监听者事件分发不分配大型对象。
- 单个同步 hook 超过 100ms 记录慢调用警告。
- registry snapshot 构建不得阻塞所有请求；切换必须为原子操作。
- 插件列表和详情页避免逐插件 N+1 查询。

## 18. 测试矩阵

### 18.1 测试层级

- **单元测试**：parser、resolver、registry、DTO、Result 和排序。
- **合同测试**：每个 Host API、事件 schema、lifecycle hook 和 contribution。
- **集成测试**：真实数据库、任务队列和 Rails 服务。
- **系统测试**：后台上传、安装、配置、启停、升级、恢复和卸载。
- **多进程测试**：两个 Web 进程、至少一个 Job 进程。
- **组合测试**：多个插件对同一事件、服务和 UI slot 扩展。
- **故障注入**：迁移失败、进程拒绝确认、任务超时、文件缺失和包损坏。
- **性能测试**：大量插件、贡献、事件订阅和权限定义。
- **CE/EE 边界测试**：CE 拒绝 EE-only manifest，CE 不加载实时适配器。

### 18.2 必测生命周期路径

| 场景 | 预期 |
| --- | --- |
| 全新安装成功 | generation 一致，贡献可见 |
| 安装步骤中断 | 可重试或完整回滚 |
| 同版本重新安装 | 按明确策略修复或拒绝，不重复迁移 |
| 兼容升级 | 设置和数据保留 |
| 不兼容升级 | 静态阶段拒绝，不影响当前版本 |
| 新进程加载失败 | 不提交新 active generation |
| 停用插件 | hook、任务和 UI contribution 停止 |
| 重新启用 | 原设置、授权和数据恢复 |
| 卸载保留数据 | 代码移除，数据可识别 |
| 卸载清除数据 | journal 完整，无孤儿贡献 |
| 回滚上一版本 | 代码、registry 与 schema 兼容 |
| 文件被修改 | health 报告指出具体文件 |

### 18.3 多插件组合

至少维护以下固定夹具：

- 两个插件按优先级修改同一 filter。
- 三个插件组成 service decorator chain。
- 一个插件依赖另一个插件的贡献。
- 两个插件声明互斥。
- `before`/`after` 形成循环。
- 上游插件升级导致依赖范围失效。
- 某插件 hook 抛错但其他隔离型事件仍继续。
- 某插件在事务回滚后不得收到 after-commit event。

### 18.4 兼容性矩阵

- 当前宿主版本 + 当前 SDK。
- 当前宿主版本 + 上一稳定 SDK 插件。
- 下一宿主版本预览 + 当前稳定插件。
- CE 插件安装到 EE。
- EE-only 插件安装到 EE。
- EE-only 插件安装到 CE，必须静态拒绝。
- 开发环境 reload 与生产不可变加载。

## 19. CE 与 EE 目标能力归属矩阵

下表描述最终目标和代码归属，不代表当前完成度；当前实现状态以第 3 节“当前基线”为准。

| 能力 | CE 目标 | EE 目标 | 归属 |
| --- | --- | --- | --- |
| Manifest、依赖和生命周期 | 是 | 继承 | CE |
| 论坛 Host API | 是 | 继承 | CE |
| Identity 与全局身份组 API | 是 | 继承 | CE |
| Commerce API | 是 | 继承 | CE |
| Jobs、通知、邮件和存储 | 是 | 继承 | CE |
| 权限、设置、导航和 UI contributions | 是 | 继承 | CE |
| 插件后台与 Arco UI | 是 | 继承后可扩展 | CE |
| WebSocket/实时事件 | 否 | 是 | EE |
| 实时发帖广播 | 否 | 是 | EE |
| 频道聊天与频道在线状态 | 否 | 是 | EE |
| EE 实时插件 SDK | 否 | 是 | EE |
| EE 实时参考插件 | 否 | 是 | EE |

边界门禁：

- CE 代码搜索和依赖图中不得出现 EE realtime adapter。
- CE manifest schema 可以识别 `edition: ee`，但不得包含其运行实现。
- EE 合并 CE 后，通过下游注册机制追加 realtime Host API。
- 通用 DTO 若被 EE 使用，仍在 CE 保持与实时无关的领域含义。

## 20. 风险清单

| 风险 | 早期信号 | 处理措施 | 发布门禁 |
| --- | --- | --- | --- |
| 并行代理覆盖未提交改动 | 同一文件出现多组无关 diff | 文件所有权、先查状态、主代理集成 | 无来源不明 diff |
| 插件 API 泄漏内部模型 | 文档或测试直接断言 ActiveRecord | DTO/Result 边界和合同测试 | 公共 API 无内部对象 |
| 多进程 registry 不一致 | 不同进程显示不同 generation | 持久化 generation、ack、超时回滚 | 多进程故障测试通过 |
| 事务内触发外部副作用 | 回滚订单仍发出通知 | outbox/after-commit | 回滚副作用测试通过 |
| 装饰器重复调用核心服务 | 重复退款、重复发帖 | 框架级 once guard、幂等键 | 双调用回归测试通过 |
| 升级留下半完成 schema | lifecycle 卡在 upgrading | step journal、兼容迁移、恢复命令 | 中断恢复测试通过 |
| 停用后仍有孤儿任务 | 队列持续执行旧 handler | 任务归属与 generation 检查 | 停用任务测试通过 |
| UI 插件导致后台白屏 | 单模块异常传播到根应用 | contribution error boundary | 失败隔离系统测试 |
| I18N 持续缺失 | 页面出现 phrase key | 构建覆盖率与默认语言门禁 | 默认语言 100% |
| 文档再次漂移 | 多份文档描述矛盾 | 生成合同矩阵、文档测试 | 发布前一致性检查 |
| EE 实时代码回流 CE | CE 出现 ActionCable/WS 插件入口 | edition 测试与路径审查 | CE/EE 边界测试通过 |
| 把信任模型误做成沙箱项目 | 工作项出现签名/扫描/隔离 | 明确非目标，关闭此类 Issue | 路线图范围审查 |

## 21. 可转成 Issue 的任务清单

本节是第 4 节实施阶段的 Issue 映射，不另行定义当前状态。

### 稳定化

- `PLUG-001`：盘点当前插件分支、未提交 WIP 和公共接口。
- `PLUG-002`：冻结 manifest schema v1 与 canonical digest。
- `PLUG-003`：冻结并审计现有 service decorator chain 合同。
- `PLUG-004`：在已接入论坛发帖服务的基础上继续接入首批具名核心服务。
- `PLUG-005`：建立现有 SDK 合同测试。
- `PLUG-006`：修复三份插件文档漂移。
- `PLUG-007`：生成 CE/EE/API 稳定性合同矩阵。

### Host API

- `PLUG-101`：Identity DTO、查询与权限判定。
- `PLUG-102`：全局身份组与插件权限贡献。
- `PLUG-103`：插件设置 schema 与版本化存储。
- `PLUG-104`：Jobs API 与任务归属。
- `PLUG-105`：通知与邮件 API。
- `PLUG-106`：Webhook 与可靠重试。
- `PLUG-107`：插件文件和命名空间存储。
- `PLUG-111`：Commerce catalog API。
- `PLUG-112`：Order API 与状态迁移。
- `PLUG-113`：Inventory API 与并发控制。
- `PLUG-114`：Refund API 与幂等。
- `PLUG-115`：Fulfillment provider 扩展点。
- `PLUG-116`：Commerce after-commit 事件目录。

### Contributions 与 UI

- `PLUG-201`：统一 contribution descriptor 与排序。
- `PLUG-202`：权限和设置 contributions。
- `PLUG-203`：导航、页面和操作 contributions。
- `PLUG-204`：任务与事件 contributions。
- `PLUG-205`：I18N phrase contribution 和覆盖率。
- `PLUG-206`：前端资源 manifest 与 UI slots。
- `PLUG-207`：Arco 插件详情和诊断页。
- `PLUG-208`：Arco 插件配置与权限页。
- `PLUG-209`：contribution 冲突可视化。

### 生命周期

- `PLUG-301`：持久化 lifecycle state machine。
- `PLUG-302`：step journal 与幂等恢复。
- `PLUG-303`：immutable registry snapshot。
- `PLUG-304`：desired/active generation。
- `PLUG-305`：Puma/Sidekiq process ack。
- `PLUG-306`：超时与自动回滚。
- `PLUG-307`：文件 manifest 和健康检查。
- `PLUG-308`：保留数据与清除数据卸载模式。

### 工具与生态

- `PLUG-401`：`plugin:create`。
- `PLUG-402`：`plugin:validate`。
- `PLUG-403`：`plugin:test`。
- `PLUG-404`：`plugin:build` 与可复现产物。
- `PLUG-405`：`plugin:health`。
- `PLUG-411`：Hello/Event 参考插件。
- `PLUG-412`：Forum Extension 参考插件。
- `PLUG-413`：Commerce Fulfillment 参考插件。
- `PLUG-414`：EE 实时参考插件，仅在 EE 仓库。

### 集成与发布

- `PLUG-501`：多插件组合冲突套件。
- `PLUG-502`：生命周期故障注入套件。
- `PLUG-503`：多进程系统测试环境。
- `PLUG-504`：上一稳定 SDK 兼容测试。
- `PLUG-505`：CE/EE edition 边界检查。
- `PLUG-506`：API changelog 与弃用检查。
- `PLUG-507`：正式发布清单和恢复演练。

## 22. 推荐执行波次

本节把第 4 节与第 21 节映射为执行模板；已完成项按第 3 节基线执行审计和回归，而不是重复实现。

### 波次 0：冻结基线

由主代理独占执行：

1. 保存当前 Git 状态、分支、未提交文件和测试基线。
2. 记录已完成的 service decorator 基线，并标记后续具名服务接入与审核修复的文件所有者。
3. 运行现有插件测试，记录失败而不先大范围重构。
4. 建立 `PLUG-*` Issue 或等价任务记录。

退出条件：

- 每个未提交文件都有明确所有者。
- 当前失败可以稳定复现。
- P0 公共合同范围已确定。

### 波次 1：稳定运行时

- 主代理：集成与测试门禁。
- 代理 A：`PLUG-002` 至 `PLUG-005`。
- 代理 B：`PLUG-101`、`PLUG-102`、`PLUG-103`。
- 代理 D：`PLUG-006`、`PLUG-007`、后台只读诊断原型。

退出条件：

- service decorator 合同已冻结，首个具名服务接入及组合回归通过。
- manifest、事件、论坛 API 和生命周期基线有合同测试。
- 文档与实现一致。

### 波次 2：领域 API 与 contributions

- 主代理：组合测试和接口审查。
- 代理 B：Jobs、通知、邮件、存储。
- 代理 C：Commerce API。
- 代理 D：contribution registry 上层协议和 Arco 页面。

退出条件：

- Identity/Commerce/Jobs API 通过合同测试。
- 权限、设置、导航、任务和 I18N 可由插件声明。
- CE 实时能力扫描为零。

### 波次 3：生产生命周期

- 主代理：搭建多进程验证环境。
- 代理 A：state machine、generation、ack 和 rollback。
- 代理 B：任务 generation 与 outbox。
- 代理 D：生命周期历史、健康状态和恢复 UI。

退出条件：

- 多进程启停和升级成功。
- 部分进程失败可自动回滚。
- 中断操作可恢复。

### 波次 4：开发者生态与发布

- 主代理：完整 E2E、CE→EE 合并验证。
- 代理 A：健康检查和性能优化。
- 代理 C：Commerce 参考插件。
- 代理 D：CLI、其余参考插件和最终文档。

退出条件：

- M1 至 M4 全部满足。
- 三个 CE 参考插件和一个 EE 参考插件通过各自 E2E。
- 发布清单和回滚演练完成。

## 23. Issue 开工与完成模板

### 开工条件

- 任务目标、非目标和 edition 已写明。
- 输入输出合同已确定。
- 文件所有者唯一。
- 已列出受影响的 API、事件、权限和数据。
- 已有可执行的失败用例或验收场景。
- 已检查工作区，无覆盖他人未提交改动的风险。

### 每次实现必须提交的证据

- 实现代码。
- 单元或合同测试。
- 至少一个失败路径测试。
- 涉及状态变化时的恢复/幂等测试。
- 公共行为变化对应的文档或 changelog。
- 实际运行命令与结果摘要。
- 若为 UI，提供关键页面宽屏和窄屏验证截图。

### 完成条件

- 所属测试和全量相关测试通过。
- `git diff --check` 通过。
- 没有临时日志、调试路由、硬编码 phrase 或遗留 TODO。
- 未新增 CE 实时依赖。
- 未新增沙箱、签名、发布者审查或恶意扫描范围。
- 管理后台能解释失败，而不是只显示通用 500。
- 主代理完成跨工作包集成检查。

## 24. 首轮代理任务指令

以下文本是第 22 节执行模板的可派发版本；代理开始前必须以第 3 节基线刷新已完成项。

### 代理 A 指令

> 只负责插件 runtime/lifecycle。先只读检查 `lib/mcweb/plugins/definition.rb`、`registry.rb` 与 service decorator 测试，保留并审计已完成的装饰器协议、确定性调用链、核心只调用一次保护、递归保护、异常语义和组合测试；不要重复实现。继续冻结合同、扩展具名服务接入并补组合回归。不要修改 Identity、Commerce 或后台 UI。遇到 runtime 缺陷直接修复并加回归测试。完成后报告修改文件、合同变化、测试命令和剩余风险。

### 代理 B 指令

> 只负责 Identity/Site/Jobs 基础 Host API。新增不可变 DTO、Result、全局身份组与权限查询、插件设置 schema，并补合同测试。复用核心策略，不直接暴露 ActiveRecord。不得引入 WebSocket 或实时事件，不修改 plugin registry 核心，也不覆盖其他未提交改动。遇到所属范围缺陷直接修复并加回归测试。

### 代理 C 指令

> 只负责 Commerce Host API。实现 catalog/order/inventory/refund/fulfillment 的版本化 DTO 和服务适配，所有写操作使用核心领域服务、事务、幂等键和 after-commit。重点覆盖重复退款、重复履约、库存并发和事务回滚测试。不要修改通用 registry、Identity 或后台 UI。遇到 Commerce 缺陷直接修复并加回归测试。

### 代理 D 指令

> 只负责 contributions、管理后台与 DX。定义权限、设置、导航、页面、任务、I18N 和 UI slot schema；使用 Arco Design 实现插件详情、配置和诊断页面；同步修正文档。避免全局 CSS 和宿主 DOM monkey patch。底层 registry 如需变化，先把接口需求交给主代理/代理 A，不直接并行修改。遇到本范围 UI、I18N 或文档缺陷直接修复并验证宽窄屏。

### 主代理集成指令

> 维护文件所有权和任务状态，不与子代理同时修改同一实现。每个波次结束后合并结果，运行组合、故障恢复和 CE/EE 边界测试；缺陷退回唯一所有者修复。EE 必须通过合并 CE 提交保持真实下游关系。不得把“安装即信任”扩展成沙箱、签名或市场安全审核项目。
