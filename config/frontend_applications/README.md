# Frontend application registry

This registry is a CE-owned contract inherited through ordinary `CE -> EE -> EE-PVP`
merges. Base and contribution JSON files remain the only manifest source of truth.
Downstream editions add their manifests and adapters; they do not maintain a copy
of the compiler or a manually generated browser registry.

## Build and repository checks

`scripts/frontend-application-registry-compiler.ts` contains the complete JavaScript
manifest validation previously performed during browser startup: schema keys,
resource and adapter ownership, component claims and projections, route overlaps,
shared-action sources and recovery routes, renderer identity, launchers, contribution
navigation, and representative budget paths/components. It runs before every Vite
build and from `npm run check:frontend-boundaries`. Missing required files or invalid
manifests fail the check/build; there is no last-good snapshot or production bypass.

Vite's `virtual:mcweb/frontend-applications` module contains only the validated
serializable descriptors. Nothing is generated into the working tree. A final
bundle guard rejects raw manifest JSON or the build-only compiler/loader/plugin in
browser chunks. The focused JavaScript contracts are part of `npm run test:javascript`.

## Runtime and development

`app/javascript/lib/frontendApplicationRegistry.ts` is the small shared runtime used
by both the compiler and browser, so route matching and component resolution have
one implementation. It freezes the complete snapshot, including nested navigation
grant arrays. Runtime application/component ownership checks, document identity,
`X-McWeb-Application` request headers, shared-action source checks, positive page
resolvers and adapter diagnostics are unchanged. Public descriptor fields, including
contribution budget witnesses used by adapter diagnostics, remain available.

During development, adding, changing or deleting a registry JSON file invalidates
the virtual module and reloads the document. The next module request recompiles all
manifests; invalid input produces a source-specific error instead of serving stale
ownership rules. Compiler/plugin edits are Vite configuration dependencies and use
Vite's configuration restart path.
