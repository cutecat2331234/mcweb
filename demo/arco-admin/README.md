# Arco Admin standalone demo

Preview McWeb's Arco Design Vue admin UI **without Rails, Inertia, or a backend**.

## Run

From the project root:

```bash
npm install   # if you haven't already
npm run demo:arco
```

Vite opens **http://localhost:5173** (or the next free port if 5173 is taken).

## What's included

- Arco Pro–style sidebar layout with collapsible menu
- KPI stat cards
- Filter form (Input, Select, DatePicker)
- Data table with static sample orders
- Modal demo
- Dark mode toggle (syncs `html.dark` + Arco `arco-theme`)

## Files

| File | Purpose |
|------|---------|
| `index.html` | Vite entry HTML |
| `main.ts` | Mounts Vue + Arco |
| `App.vue` | Root component |
| `DemoLayout.vue` | Standalone admin shell |
| `DemoPage.vue` | Demo content (adapted from `app/javascript/pages/Admin/ArcoDemo/Index.vue`) |
| `data.ts` | Static demo stats & table rows |
| `demo.css` | Minimal Tailwind for utility classes |

Vite config: `vite.arco-demo.config.ts` at repo root.

## Production build (optional)

```bash
npx vite build --config vite.arco-demo.config.ts
npx vite preview --config vite.arco-demo.config.ts
```

Output goes to `demo/arco-admin/dist/`.
