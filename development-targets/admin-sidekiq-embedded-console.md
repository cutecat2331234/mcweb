# Embedded Sidekiq administrator console

## Ownership and delivery boundary

- Owner: CE.
- Reason: administrator authentication, authorization, browser framing, and the Sidekiq operations surface are shared platform contracts inherited by every edition. EE and EE-PVP must consume the CE history through ordinary `CE -> EE -> EE-PVP` merges rather than reimplementing the console.
- Scope: the existing `/jobs` Sidekiq Web mount, its administrator host page, dedicated permissions, same-origin session gate, safe embedded deep links, return navigation, and observable loading/error states.
- Excluded: queue semantics, job payload redesign, Sidekiq UI replacement, downstream product concepts, and a new visual system.
- Validation boundary: this task writes source and test contracts and performs static checks only. Local tests, builds, installs, generators, services, browser acceptance, migration execution, commits, pushes, and merges remain deferred to CNB.

## Current state and minimum gap

CE already renders `/jobs` inside the Arco administrator shell and constrains the child document to same-origin framing. The remaining minimum gap is that the generic `system.jobs.*` permissions silently authorize broader native Sidekiq operations, the mounted Rack application does not share every administrator session gate, the host cannot preserve a Sidekiq subpath across refresh/share, the standalone console has no explicit route back to the administrator shell, and iframe `load` alone cannot distinguish an operational page from an HTTP error document.

## Functional and security requirements

- [x] Use dedicated `system.sidekiq.read` and `system.sidekiq.manage` permissions. A mutation requires both read and manage; generic allowlisted-job permissions must no longer authorize native Sidekiq mutations.
- [x] Preserve upgrade access by granting the new read permission to existing role/group holders of `system.jobs.read` or `system.jobs.manage`, and the new manage permission to existing holders of `system.jobs.manage`.
- [x] Require the same active, eligible Rails session used by the administrator application, including the mandatory TOTP-setup gate, `admin.access`, and the `system` administrator module.
- [x] Keep authentication in the signed HttpOnly same-origin cookie/session. Never accept a frame origin, session token, credential, or arbitrary URL from request parameters or Inertia props; every state-changing Sidekiq request must also come from the same browser origin.
- [x] Keep the parent document restricted to same-origin frame sources and every Sidekiq response restricted to same-origin ancestors; outside sites must not be able to frame the console.
- [x] Represent an embedded Sidekiq subpath under `/admin/system/sidekiq/*path`, validate it against Sidekiq and Sidekiq Cron HTML routes, preserve only bounded and semantically valid query fields, and synchronize successful in-frame navigation and its Inertia history props so refresh/share/back restore the same view. Keep the native raw profile-data URL available only as the safe standalone fallback; never accept it as a ready embedded page or administrator deep link.
- [x] Configure Sidekiq's built-in application return URL to the protected administrator host. If used from inside the iframe, promote that navigation to the top-level document instead of nesting an administrator shell.
- [x] Require a host-owned DOM marker that is injected only into successful Sidekiq HTML before marking the iframe ready. HTTP errors, permission loss, JSON endpoints, and Redis/Sidekiq failures must remain an error state with retry rather than being accepted solely because an iframe `load` event fired.
- [x] Keep the existing Arco shell, loading/error/retry presentation, responsive host geometry, Simplified Chinese and English Admin-owned copy, and a standalone fallback that opens the current safe deep link without an opener or referrer.

## Deferred CNB acceptance

- Apply the permission migration on a production-shaped database and verify legacy role and identity-group backfill without broadening unrelated permissions.
- Run focused Ruby, JavaScript, permission-catalog, routing, CSP, and i18n contracts plus the full required CE suite.
- Exercise read-only and manage operators, missing permissions/module, expired or revoked sessions, banned/deleted accounts, and mandatory-TOTP accounts against both the host route and real `/jobs/*` responses.
- Verify root and nested queues/retries/scheduled/metrics paths, query filters, refresh/share, browser back/forward, standalone return, and permission changes during an open session.
- Verify 404, 500, Redis unavailable, timeout, retry, and recovery states; confirm a failed child document is not shown as a ready console.
- Confirm `frame-src 'self'`, `frame-ancestors 'self'`, `X-Frame-Options: SAMEORIGIN`, cross-site mutation rejection, mobile/keyboard usability, and absence of authentication material in URLs, props, HTML, logs, and referrers.
