# Arco Design Vue (McWeb vendored fork)

This directory contains the full **Arco Design Vue** component library source, vendored into the McWeb repository for customization (二开).

- **Upstream:** https://github.com/arco-design/arco-design-vue
- **Package:** `@arco-design/web-vue` (`packages/web-vue/`)
- **McWeb convention:** import runtime components via `@mcweb/ui` (see `docs/UI_COMPONENT_LIBRARY.md`)

## Why vendored?

McWeb treats Arco as the unified admin UI system. Keeping source in-tree allows:

- Fork-specific component tweaks without waiting on upstream releases
- Auditable, reproducible builds
- A single place to align tokens with McWeb branding

## Runtime vs source

The admin Vite entry currently resolves `@mcweb/ui` to the published npm build (`node_modules/@arco-design/web-vue`) so the app builds without running Arco's monorepo toolchain.

To develop against **source** instead:

1. Install [pnpm](https://pnpm.io/) and run `pnpm install` in this directory
2. Build the web-vue package: `pnpm --filter @arco-design/web-vue run build`
3. Point the `@mcweb/ui` alias in `vite.config.ts` at `vendor/arco-design-vue/packages/web-vue/components/index.ts` (and add Less support if importing raw `.vue` sources)

## Layout reference

Arco Pro layout patterns live in `vendor/arco-design-pro-vue/` (reference only; McWeb admin uses Inertia, not vue-router).

## License

MIT — see upstream `LICENSE` in this repository.
