# McWeb 前台模板规范（TEMPLATE_SPEC）

本文档是 `THEME_GUIDE.md` 的**正式技术规范**，定义 ZIP 模板的契约、作用范围、安全边界与已知限制。

## 1. 设计目标

| 目标 | 说明 |
|------|------|
| 可换肤 | 官网与用户前台（论坛/商城/账户等）可通过 ZIP 更换外观 |
| 安全隔离 | **后台 Admin 永不受模板影响**（独立 `admin.ts` 构建） |
| 免构建 | 主题作者无需 `npm run build`，上传 ZIP 即可生效 |
| 双域独立 | `website` 与 `portal` 可激活**不同**模板 |

## 2. 作用范围矩阵

### 2.1 受模板影响的区域（`portal` scope）

| 控制器命名空间 | 示例路径 |
|----------------|----------|
| `Community::*` | `/app/forum/*` |
| `Commerce::*` | `/app/store/*` |
| `Identity::*` | `/app/identity/*` |
| `Payments::*` | `/app/payments/*` |
| `Minecraft::*` | Minecraft 相关页 |

布局：`PortalLayout.vue`（侧栏 + 顶栏 + 主内容）

### 2.2 受模板影响的区域（`website` scope）

| 控制器命名空间 | 示例路径 |
|----------------|----------|
| `Website::*` | `/`、`/pages/*`、`/blog/*` |

布局：`WebsiteLayout.vue`（官网顶栏/页脚 + 主内容）

### 2.3 不受影响

| 区域 | 原因 |
|------|------|
| `/admin/*` | 独立 Vite 入口 `admin.ts`，不注入 `activeTemplate` |
| API / Webhook | 无 HTML 布局 |
| 邮件模板 | 另一套系统 |

### 2.4 与 `Website::Theme` 的关系

数据库中存在 `website_themes` 表及 `website_pages.website_theme_id` 字段，**当前前台未读取**。  
**唯一生效的主题系统**为 `Frontend::Template`（ZIP 上传）。`Website::Theme` 视为遗留/未接入，不得与 ZIP 模板混用。

## 3. ZIP 包契约

### 3.1 目录结构

```
{key}.zip
├── manifest.json          # 必填
├── styles/
│   └── theme.css          # 推荐
├── assets/
│   ├── logo.svg           # 可选
│   └── favicon.ico        # 可选
└── slots/
    ├── website_header.html
    ├── website_footer.html
    └── portal_header_extra.html
```

### 3.2 manifest.json  schema

```json
{
  "name": "人类可读名称",
  "key": "kebab-case-唯一标识",
  "version": "1.0.0",
  "scopes": ["website", "portal"],
  "tokens": {
    "primary_color": "#38bdf8"
  },
  "assets": {
    "css": ["styles/theme.css"],
    "logo": "assets/logo.svg",
    "favicon": "assets/favicon.ico"
  },
  "slots": {
    "website_header": "slots/website_header.html",
    "website_footer": "slots/website_footer.html",
    "portal_header_extra": "slots/portal_header_extra.html"
  }
}
```

| 字段 | 必填 | 约束 |
|------|------|------|
| `name` | 是 | 1–80 字符 |
| `key` | 是 | 小写字母、数字、连字符；重装同 key 覆盖 |
| `version` | 是 | SemVer |
| `scopes` | 是 | 仅允许 `website`、`portal`；**禁止** `admin` |
| `tokens` | 否 | 键名 snake_case，值注入为 CSS 变量 |
| `assets.css` | 否 | 相对路径数组，仅 `.css` |
| `assets.logo` / `favicon` | 否 | 图片相对路径 |
| `slots.*` | 否 | 必须位于 `slots/` 且为 `.html` |

### 3.3 允许的文件扩展名

`.css` `.json` `.png` `.jpg` `.jpeg` `.svg` `.webp` `.gif` `.woff` `.woff2` `.html`（仅 `slots/`）

### 3.4 禁止

- 可执行/源码：`.vue` `.js` `.ts` `.rb` `.erb` 等
- 路径穿越：`..`
- 路径含 `admin`、`Admin`、`pages/Admin`
- 单包超过 **20MB** 或 **200** 个文件

## 4. Token 命名与 CSS 变量

manifest `tokens` 键名 `snake_case` → 前端变量 `--template-{kebab-case}`：

| manifest | CSS 变量 |
|----------|----------|
| `primary_color` | `--template-primary-color` |
| `website_bg` | `--template-website-bg` |
| `portal_header_bg` | `--template-portal-header-bg` |

### 4.1 推荐 token 表

| Token | 建议用途 |
|-------|----------|
| `primary_color` | 主色、链接、强调 |
| `website_bg` | 官网页面背景 |
| `website_text` | 官网正文色 |
| `portal_header_bg` | Portal 顶栏背景 |
| `portal_sidebar_bg` | 侧栏背景（需自定义 CSS 命中） |
| `border_color` | 边框色 |

注入位置：布局根元素 `style`（`tokenStyle`），与 `useTheme` 明暗模式**独立**。

### 4.2 CSS 作用域约定

| Scope | 根类名 | 说明 |
|-------|--------|------|
| website | `.website-page` | 已在 `WebsiteLayout` 使用 |
| portal | `.portal-themed` | 建议在自定义 CSS 中以此限定选择器 |

自定义 CSS 示例：

```css
.website-page {
  background: var(--template-website-bg, #0f172a);
}

.portal-themed header.portal-header {
  background: var(--template-portal-header-bg, color-mix(in oklch, var(--background) 94%, transparent));
}
```

## 5. HTML 插槽

| 插槽 key | Scope | 行为 |
|----------|-------|------|
| `website_header` | website | **替换**默认 `<header>`（有插槽时） |
| `website_footer` | website | **替换**默认 `<footer>` |
| `portal_header_extra` | portal | 在顶栏**上方**追加 HTML（不替换侧栏/顶栏结构） |

### 5.1 消毒白名单

经 `Frontend::SanitizeTemplateSlot` 处理：

- **允许标签**：`p br strong em u s del h1–h6 ul ol li blockquote pre code a img span div nav header footer section`
- **禁止**：`script` `iframe` `style` `on*` 事件属性
- **链接**：`http` `https` `mailto` `/` 开头
- **图片**：`http` `https` `/` 开头（可用 `/theme-assets/{key}/...`）

### 5.2 插槽内引用主题资源

```
<img src="/theme-assets/starter/assets/banner.png" alt="">
```

由 `Frontend::BuildTemplateAssetUrl` 提供只读路由：`GET /theme-assets/:template_key/*path`

## 6. 激活与预览

| 操作 | 机制 |
|------|------|
| 激活官网 | `SiteSetting` → `frontend.active_website_template` |
| 激活前台 | `SiteSetting` → `frontend.active_portal_template` |
| 预览 | `?preview_template={key}`（需 `website.templates.manage` 权限，session 级） |
| 停用 | 后台「停用」或删除模板（删除时自动清除激活） |

存储目录：`MCWEB_TEMPLATE_DIR`（默认 `/var/lib/mcweb/templates`），与 release 目录分离。

## 7. 前端数据流

```
ZIP 上传 → InstallTemplateArchive → DB + 磁盘
                ↓
ActivateTemplate → SiteSetting
                ↓
ResolveActiveTemplate → SerializeActiveTemplate
                ↓
Inertia share: activeTemplate → useActiveTemplate()
                ↓
TemplateAssets (CSS/favicon) + Layout (tokens/slots/logo)
```

`activeTemplate` 结构：

```typescript
{
  key: string
  name: string
  version: string
  scope: 'website' | 'portal'
  tokens: Record<string, string>   // 已转为 --template-* 内联样式
  cssUrls: string[]
  logoUrl?: string
  faviconUrl?: string
  slots: Record<string, string | null>
}
```

## 8. 能力边界（诚实声明）

### 8.1 当前**可以**定制

- 颜色 token、自定义 CSS
- Logo、Favicon
- 官网页眉/页脚 HTML
- Portal 顶栏上方额外 HTML 条

### 8.2 当前**不能**定制

- Vue 页面结构、路由、组件逻辑
- Portal 侧栏菜单项、布局分区
- 按用户/按分区使用不同主题
- 在线可视化编辑器
- 后台 Admin 任意界面

### 8.3 规划中的扩展（未实现）

- `portal_footer` / `portal_sidebar_extra` 插槽
- `portal-themed` 根类正式挂载
- 废弃或接入 `Website::Theme`
- 插槽内 `{{theme_asset:path}}` 占位符

## 9. 权限与后台入口

- 权限：`website.templates.manage`
- 路径：**后台 → 官网 → 前台模板**（`/admin/frontend/templates`）
- 操作：上传 ZIP、激活（分 scope）、预览、删除

## 10. 示例包

- 源码：`public/template-starter/`
- 构建：`bin/build-starter-template` → `public/template-starter/starter.zip`
- 文档：`THEME_GUIDE.md`（快速上手）

## 11. 版本与兼容

- 同 `key` 重装：覆盖磁盘文件，更新 `manifest` 与 `checksum`；**已激活状态保留**
- 模板 `version` 仅作展示，系统不做 SemVer 迁移
- McWeb 升级时：模板 API 向后兼容；新增插槽/token 为可选字段

---

**相关文件**

| 用途 | 路径 |
|------|------|
| 模型 | `app/models/frontend/template.rb` |
| 安装/校验 | `app/services/frontend/install_template_archive.rb` |
| 激活 | `app/services/frontend/activate_template.rb` |
| 前端消费 | `app/javascript/lib/useActiveTemplate.ts` |
| 测试 | `test/services/frontend_template_test.rb` |
