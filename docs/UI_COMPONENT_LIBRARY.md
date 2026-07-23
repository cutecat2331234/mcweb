# McWeb UI component library

McWeb standardizes on **Arco Design Vue** for admin (and future plugin) interfaces.

## Vendored source

| Path | Purpose |
|------|---------|
| `vendor/arco-design-vue/` | Full `@arco-design/web-vue` source for fork/customization |
| `vendor/arco-design-pro-vue/` | Arco Pro layout reference (not executed as an SPA) |

See also `vendor/arco-design-vue/README.mcweb.md`.

## Import convention

Use the **`@mcweb/ui`** alias — do not deep-import from `node_modules` in application code.

```ts
import ArcoVue, { Button, Table } from '@mcweb/ui'
```

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

The **portal** entry (`entrypoints/inertia.ts`) keeps the existing shadcn/reka-ui stack. New portal work should not pull Arco unless we explicitly migrate.

## Admin layout

| Layout | Stack | Use when |
|--------|-------|----------|
| `layouts/AdminLayout.vue` | shadcn + Tailwind | Legacy admin pages (~55 pages) |
| `layouts/ArcoAdminLayout.vue` | Arco + Inertia | New Arco-based admin / plugins |
| `components/admin-pro/ProLayout.vue` | Element Plus (POC) | EP redesign demos only |

Example Arco page:

```vue
<script setup lang="ts">
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
defineOptions({ layout: ArcoAdminLayout })
</script>
```

Preview:

- **Standalone (no Rails):** `npm run demo:arco` → http://localhost:5173 — see `demo/arco-admin/README.md`
- **In-app:** `/admin/arco-demo` (requires Rails + admin entry)

## Rule for new work

**Plugins and new admin features must use `@mcweb/ui` (Arco)** — not ad-hoc CSS frameworks or one-off component kits. Prefer `ArcoAdminLayout` for shell chrome.

Exceptions (document in PR):

- Portal/community surfaces (shadcn until a deliberate migration)
- Temporary POC pages clearly marked for removal

## Vite aliases (`vite.config.ts`)

- `@mcweb/ui` → npm `@arco-design/web-vue` (default runtime)
- `@arco-design/web-vue-source` → `vendor/arco-design-vue/packages/web-vue/components` (二开; requires Arco build or Less pipeline)

To switch runtime to vendored source after building Arco, repoint `@mcweb/ui` to the source `components/index.ts` path.

## Build / dev

```bash
npm install
bin/dev          # or: bundle exec rails server + bin/vite dev
```

Admin assets compile through `app/javascript/entrypoints/admin.ts` (Arco + optional Element Plus POC styles).

Smoke-build admin bundle:

```bash
npx vite build --mode development
```

## Customizing components

1. Edit files under `vendor/arco-design-vue/packages/web-vue/components/`
2. Build the package (see vendored README) or temporarily repoint `@mcweb/ui` to source
3. Keep changes minimal and documented; consider upstreaming generic fixes
