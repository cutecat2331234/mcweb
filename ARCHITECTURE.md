# 架构说明

## 模块边界

```
app/
  models/          # 按领域命名空间：Website、Community、Commerce、Minecraft、Payments
  services/        # 业务命令对象，Controller 保持精简
  jobs/            # Active Job + Solid Queue
  components/ui/   # 通用设计系统（直角、无卡片）
  controllers/     # 按模块分命名空间
```

## 数据流

### 支付流程

1. 用户下单 → `Commerce::CreateOrder`
2. 创建 `Payments::Record` → Provider 发起支付
3. Webhook → `Payments::WebhookProcessor`（签名验证 + 事件幂等）
4. `Commerce::ConfirmPayment`（行锁 + 状态检查）
5. `Commerce::FulfillOrderJob` → 创建 `Commerce::Fulfillment`

### 发货流程

1. `Commerce::CreateFulfillment` 生成唯一 `delivery_id`
2. `Minecraft::DispatchFulfillmentJob` 创建 Connector 任务
3. 插件拉取任务 → 本地检查 `delivery_id` → 执行命令
4. 回调确认 → 更新 Fulfillment 状态

两边均保证幂等：数据库唯一约束 + 状态机检查。

## 缓存

- 公共官网区块、商品列表使用 Solid Cache
- 用户权限、购物车不共享缓存

## 后台任务队列

`critical` / `payments` / `minecraft` / `mailers` / `notifications` / `media` / `maintenance`

## 前端架构（官网 vs 业务 Portal）

同一 Rails 应用内采用 **双视觉体系**，通过 Inertia.js + Vue 3 渲染，后台管理暂保留 ERB。

| 区域 | 布局 | 风格 | 技术 |
|------|------|------|------|
| 官网首页 | `WebsiteLayout.vue` | 营销风：渐变、动效、品牌叙事 | `website.css` |
| 论坛/商城/登录 | `PortalLayout.vue` | 功能优先：shadcn-vue 组件、直角表格 | `portal.css` + shadcn |
| 安装向导 / 后台 | ERB 布局 | 运维与表单 | Tailwind + ViewComponent |

```
app/javascript/
  entrypoints/inertia.ts    # Inertia 入口
  layouts/                  # WebsiteLayout / PortalLayout
  pages/                    # 按模块映射控制器 render inertia
  components/ui/            # shadcn-vue 基础组件
  styles/website.css        # 官网设计令牌
  styles/portal.css         # Portal / shadcn 设计令牌
```

构建：`bin/vite build`（生产部署在 `bin/setup` 中于 `assets:precompile` 之前执行）。

## 官网与后台样式隔离（历史 ERB）

- `application.html.erb` + `tailwind/application.css`：尚未迁移的 ERB 页面（后台、购物车等）
- `layouts/inertia.html.erb`：Vue 页面统一根布局
