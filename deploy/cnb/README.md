# CNB dependency images

McWeb CE owns the Docker-backed dependency and service caches shared by every
edition. EE inherits these files unchanged. EE-PVP selects its own Node package
directory through the quality image's downstream-package argument, but it does
not copy or redefine the shared Ruby, root npm, browser, Go, Gradle, database,
or production-acceptance cache recipes.

- `quality-dependencies.Dockerfile` contains the locked Ruby, root npm,
  Playwright Chromium, operating-system, and Docker CLI dependencies used by
  Rails, frontend, and browser gates. Its neutral downstream Node input defaults
  to `empty-node-package`; a downstream adapter may select one reviewed package
  directory and attach `MCWEB_DOWNSTREAM_NODE_MODULES` at its product path.
- `postgres-test.Dockerfile` and `redis-test.Dockerfile` pin disposable service
  images. The acceptance MinIO image remains CE-owned under `deploy/acceptance`.
- `production-acceptance-dependencies.Dockerfile` pins Ruby, Docker CLI,
  Compose v2, the PostgreSQL 18 client major, and the production bundle. The
  client major is read from `postgresql-client-cache.version`; CNB retains the
  resulting image so normal validation does not reinstall repository packages.
- `go-dependencies.Dockerfile` caches both Go module graphs while source is
  always tested and built from the checked-out commit.
- `gradle-dependencies.Dockerfile` caches JDK 8, JDK 17, Gradle, and connector
  dependencies so checked-out connector builds can run offline. Increment
  `gradle-cache.version` to refresh mutable upstream artifacts deliberately.
- The production Dockerfile's `dependencies` and `runtime-base` stages are
  consumed by CNB `docker:cache`. Use the nonnumeric Docker boolean string `T`
  for `BUILDKIT_INLINE_CACHE`: CNB normalizes quoted numeric strings in plugin
  options, while Docker accepts `T` as true.

CNB's built-in cache makes only the Dockerfile and files listed by `by`
available while building the image. Every copied lock/version input therefore
belongs in `by`; every content-changing input belongs in `versionBy`. Source,
tests, acceptance probes, and scripts that are not copied into a dependency
image must not invalidate it.

All external base images are fixed to manifest digests. Update a descriptive
tag and digest together in a reviewed commit. The Go cache and checked-out Go
source use `GOTOOLCHAIN=local`; checked-out work uses `GOPROXY=off`. Connector
work uses Gradle `--offline`; npm enters offline mode after dependency and
browser provisioning. Missing cached artifacts therefore fail rather than
silently downloading during a gate.

Git LFS remains reserved for reviewed, versioned binary assets. Do not store
`node_modules`, `vendor/bundle`, browser downloads, JDK archives, Gradle caches,
Go module caches, database images, or generated build output in Git or Git LFS.
