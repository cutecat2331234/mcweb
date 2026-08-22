# McWeb UI component library

> 版本边界（2026-07-26）：CE 与 EE 的管理后台使用相同的 UI 样式和视觉规范。
> CE 面向普通用户的 `/app` 保留原有组件栈；EE 用户前台的重写方案不适用于 CE。

McWeb standardizes on **Arco Design Vue** for admin (and future plugin) interfaces.

## Vendored source

| Path | Purpose |
|------|---------|
| `vendor/arco-design-vue/` | Full `@arco-design/web-vue` source for fork/customization |
| `vendor/arco-design-pro-vue/` | Arco Pro layout reference (not executed as an SPA) |

See also `vendor/arco-design-vue/README.mcweb.md`.

## Import convention

The admin entrypoint registers the published Arco runtime directly:

```ts
import ArcoVue from '@arco-design/web-vue'
```

Admin modules may use the **`@mcweb/ui`** alias for named component services. The alias resolves
to the same published package and gives the project one controlled seam for a future reviewed
vendor-source switch:

```vue
<script setup lang="ts">
import { Message } from '@mcweb/ui'
</script>
```

Arco global styles (admin entry only):

```ts
import '@arco-design/web-vue/dist/arco.css'
import '@/styles/arco-admin.css'
```

`arco-admin.css` is a deliberate centralized product-theme layer, not official Arco CSS. It is
limited to the admin shell, design tokens, visual hierarchy, focus/reduced-motion behavior and
cross-page component normalization that Arco props cannot express consistently. Page-scoped
CSS remains an exception and must not recreate Arco components.

The admin entry must not import `portal.css`. The **portal** entry (`entrypoints/inertia.ts`)
keeps the existing shadcn/reka-ui stack. New portal work should not pull Arco unless we
explicitly migrate.

## Admin layout

| Layout | Stack | Use when |
|--------|-------|----------|
| `layouts/AdminLayout.vue` | Arco + Inertia | Canonical persistent layout identity for every Admin page |
| `layouts/ArcoAdminLayout.vue` | Arco + Inertia | Shell implementation used only inside `AdminLayout` |
| `components/admin-pro/ProLayout.vue` | Arco + Inertia | Compatibility alias for former POC imports |

Example Arco page:

```vue
<script setup lang="ts">
import AdminLayout from '@/layouts/AdminLayout.vue'
defineOptions({ layout: AdminLayout })
</script>
```

Do not import `ArcoAdminLayout` directly from a page. Inertia preserves a layout only while its
component identity stays the same; mixing the wrapper and implementation would remount the
sidebar/header and lose local shell state during otherwise normal SPA navigation.

Preview:

- **Standalone (no Rails):** `npm run demo:arco` → http://localhost:5173 — see `demo/arco-admin/README.md`
- **In-app:** `/admin/arco-demo` (requires Rails + admin entry)

## Rule for new work

**Plugins and new admin features must use Arco** (the direct package or the `@mcweb/ui` alias
described above) — not ad-hoc CSS frameworks or one-off component kits. Prefer
the canonical `AdminLayout` for shell chrome.

Exceptions (document in PR):

- Portal/community surfaces (shadcn until a deliberate migration)
- Temporary POC pages clearly marked for removal

## Shared visual contracts

- Use Arco component props and the centralized token layers before adding CSS.
  Page-scoped CSS must solve a page-specific layout constraint and must not
  restyle an Arco component into a new visual language.
- Active navigation uses Arco's selected state. Do not add a custom leading
  stripe, a permanent focus outline, or a second selected background.
- Application surfaces do not use decorative gradients. Hover and focus must
  not translate, scale, or otherwise move cards and controls.
- A Collapse body containing bordered Descriptions or a Table is one continuous
  `--color-bg-2` surface. Keep label/header fills provided by Arco and do not
  mix transparent value cells with a differently colored Collapse body.

## Vite aliases (`vite.config.ts`)

- `@mcweb/ui` → npm `@arco-design/web-vue` (default runtime)
- `@arco-design/web-vue-source` → `vendor/arco-design-vue/packages/web-vue/components` (二开; requires Arco build or Less pipeline)

To switch runtime to vendored source after building Arco, repoint `@mcweb/ui` to the source `components/index.ts` path.

## Build / dev

```bash
npm install
bin/dev          # or: bundle exec rails server + bin/vite dev
```

Admin assets compile through `app/javascript/entrypoints/admin.ts` with the Arco runtime,
official Arco base styles and the reviewed `arco-admin.css` product-theme layer. They do not
load portal styles. Element Plus and its POC runtime dependencies have been removed.

Smoke-build admin bundle:

```bash
npx vite build --mode development
```

## Customizing components

1. Edit files under `vendor/arco-design-vue/packages/web-vue/components/`
2. Build the package (see vendored README) or temporarily repoint `@mcweb/ui` to source
3. Keep changes minimal and documented; consider upstreaming generic fixes
