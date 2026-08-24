# CNB build reliability and cache ownership

## Ownership decision

- Owner: CE for shared security findings, CNB configuration contracts, Docker dependency images, Go/Gradle caches, disposable service images, and production data-lifecycle acceptance tooling.
- Reason: these capabilities apply to every McWeb edition. They must be implemented once in CE and inherited through ordinary `CE -> EE -> EE-PVP` merges.
- EE owns only the three EE service-query findings exposed by the shared security gate.
- EE-PVP owns only PVP query/controller findings, the `pvp/site` dependency adapter, Astro runtime validation, and PVP-specific pipeline inputs. It must consume rather than recreate CE cache primitives.
- Current platform fact: CNB presently has one McWeb repository, `CNSUBTIERS/mcweb-ee-pvp`; there are no separate CE or EE CNB repositories. The downstream pipeline is therefore the current runtime witness for defects whose source owner is CE or EE.

## Verified failure baseline

The existing CNB build and its rebuild both ran against remote `main` commit
`54656c66a079d9a82fd9aa32788ad27ed2cde5c0` and failed with the same result:

- `cnb-k8g-1k0lkcjuv`, started 2026-08-23 05:00:23.
- `cnb-l74-1k0n9n4ih`, started 2026-08-23 20:32:22 as a rebuild.
- Both completed only 3 of 8 jobs. Security configuration, Go, and cached offline Gradle connector work passed.
- The latest verified logs are the input to this task. Local commits newer than that remote commit are not treated as CNB-validated.

| Failed gate | Verified failure | Owner in this task |
| --- | --- | --- |
| `static-application-quality / lint-and-static-security` | RuboCop passed 3,412 files; Brakeman 8.0.5 reported 12 warnings and exited 3. | CE 3, EE 3, EE-PVP 6 |
| `rails-full-suite-fresh-postgres / build-test-assets` | `npm --prefix pvp/site run build` completed, then the packaged-tree `npm ls --offline --ignore-scripts --all` emitted missing/extraneous results and the runtime checker exited 1. Database preparation and the Rails suite never ran. | CE dependency-image extension primitive plus EE-PVP runtime-check adapter |
| `chromium-system-acceptance` | 88 failed, 2 flaky, 2 skipped, 86 passed; failures center on screenshots, focus rings, keyboard-accessible scroll regions, unnamed InputNumber controls, and missing PVP elements. | Explicitly out of scope because the active frontend application boundary and PVP UI files must not be touched |
| `build-rails-and-astro-production-image / cache-production-dependencies` | CNB rejected `docker:cache data/buildArgs/BUILDKIT_INLINE_CACHE` as number `1`, even though YAML used quoted `"1"`. | CE cache-argument contract; EE-PVP pipeline adapter consumes it |
| `production-data-lifecycle-acceptance / Prepare` | The cached runner image could not install the pinned, removed PGDG package revision `18.6-3.pgdg12+1`; the lifecycle stages were skipped. | CE acceptance runner image |

### Security warning allocation

- CE:
  - `lib/mcweb/migrations/community_message_revision_backfill.rb:176` — SQL injection, medium confidence.
  - `app/services/account/notification_category.rb:74,80` — SQL injection, weak confidence.
- EE:
  - `ee/app/services/ee/chat/safety_preference_target_query.rb:26,69` — SQL injection, weak confidence.
  - `ee/app/services/ee/identity/effective_permission_user_scope.rb:137` — SQL injection, weak confidence.
- EE-PVP:
  - `app/controllers/pvp/tester/advanced_order_participations_controller.rb:97` — mass assignment, medium confidence.
  - `app/services/pvp/special_matching_workflow.rb:182,183` — SQL injection, medium confidence.
  - `app/services/pvp/notification_operations_query.rb:237,238,241` — SQL injection, weak confidence.

## Functional and security requirements

### Static-security findings

- Replace identifier and predicate string interpolation with Arel attributes and composed predicates where the query shape is relational.
- Bind runtime scalar values with typed Active Record query attributes; validating or converting a value before interpolating it is not sufficient for the shared Brakeman gate.
- Keep table and column choices behind existing closed allowlists, and make that closure visible in the query construction rather than suppressing the checker.
- Do not add broad Brakeman ignores, disable a check, or weaken strong parameters. A narrowly documented ignore is permitted only if a safe query cannot be expressed through supported Active Record/Arel APIs and the exact warning is demonstrably false.
- PVP participation attributes must be copied into an explicit service input hash. A controller may not forward a permitted-parameters object as an open mass-assignment payload.

### Reusable CNB cache primitives

- CE owns the reusable `.cnb.yml`, `.scanignore`, security-scan configuration, and `deploy/cnb/**` dependency-image recipes. EE inherits them without an adapter commit.
- The CE quality dependency image installs the root locked Ruby/npm/Chromium toolchain and exposes one neutral downstream Node-package extension input. CE provides an empty default package contract; EE-PVP selects `pvp/site` only in its adapter configuration.
- Cache keys include the Dockerfile and every lock/version input that changes image contents. Source, tests, probes, or scripts not copied into a dependency image must not invalidate that image.
- The Go image caches both module graphs while checked-out source remains the build input. Runtime Go work stays offline with a local toolchain.
- The Gradle image caches the wrapper, dependency graph, and JDK 8/17 toolchains; checked-out connector work stays offline. `gradle-cache.version` remains the explicit refresh input for mutable upstream artifacts.
- The production image imports dependency and runtime cache images. CNB `docker:cache` receives the nonnumeric Docker boolean string `"T"` for `BUILDKIT_INLINE_CACHE`; the final Docker build retains explicit BuildKit cache imports.
- The acceptance runner pins PostgreSQL client compatibility at major 18 and verifies `pg_dump`/`pg_restore` at image-build time. Packages come from PGDG's signed supported repository, while the CNB Docker image cache prevents repeated downloads. An explicit cache-version file controls intentional major-version refreshes.
- PostgreSQL, Redis, and MinIO service images remain digest-pinned Docker cache images and are required inputs to CNB production acceptance.
- No dependency directory, package-manager cache, browser download, JDK, database image, or generated build output may be stored in Git or Git LFS.

### EE-PVP adapter

- The PVP pipeline selects `pvp/site/package.json` and `pvp/site/package-lock.json` through the CE downstream-package extension; PVP package names and paths do not appear in CE.
- The PVP runtime checker validates committed and installed lock metadata plus required top-level tools without invoking `npm ls` across a symlink-attached dependency tree.
- Astro tests/builds, PVP static-runtime checks, PVP image assembly, and PVP browser acceptance remain downstream jobs.
- The adapter updates cache documentation to match the actual cache inputs. Acceptance harness/probe/source changes do not rebuild an image that copies only Gemfiles and the runner Dockerfile.

## Implementation tasks

- [ ] Commit this target by itself before implementation changes.
- [ ] Fix the three CE Brakeman findings without changing behavior.
- [ ] Add the CE-owned CNB configuration, scan configuration, dependency images, explicit cache-version inputs, and cache ownership documentation.
- [ ] Perform only syntax/static text inspection and `git diff --check` locally; do not run tests, test files, type checks, builds, application startup, or automated browser work.
- [ ] Commit CE implementation directly to `main` with explicit pathspec staging and no push.
- [ ] Confirm CE commits and focused paths, then merge CE into EE with an ordinary merge.
- [ ] Fix the three EE findings in an EE-only commit; do not touch concurrent Chat reporter files.
- [ ] Confirm EE commits and focused paths, then merge EE into EE-PVP with an ordinary merge.
- [ ] Resolve inherited cache/config additions in favor of the CE generic owner, then add the PVP adapter and six PVP security fixes in separate downstream commits.
- [ ] Do not touch the active frontend application-boundary, world-restore, or PVP UI paths.
- [ ] Stop after commits and report hashes, full path ranges, and all unverified CNB/browser items. Do not push, trigger, rerun, or wait for CNB.

## Deferred validation matrix

The parent task must run these checks after it chooses to push; this task does not run them:

- Brakeman reports zero new/unignored warnings and no longer reports the 12 allocated findings.
- CE/EE/PVP Ruby suites, JavaScript checks, TypeScript checks, Astro/Vite builds, Go work, and offline Gradle connector work pass in CNB.
- The quality dependency image is reused across static, Rails, and Chromium jobs; PVP Astro can build and pass the static-runtime dependency contract from the attached image.
- Production dependency/runtime cache stages accept the inline-cache argument and the final multi-stage image imports both caches.
- The production acceptance runner builds with PostgreSQL 18 tools, reuses all service images, and completes fresh install, upgrade, object storage, Redis, backup, and restore probes.
- The 88 Chromium failures remain open until the owning frontend/UI work is integrated and are later checked in the user's real application and Edge session.
- EE contains the exact CE commits and EE-PVP contains the exact CE and EE commits through ordinary merges.
