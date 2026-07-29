# Trusted Ruby plugin Marketplace operations

McWeb's Marketplace backend installs reviewed Ruby plugin ZIP files into the
deployment plugin directory. It is an operations API and Rake interface, not a
sandbox: after activation, `plugin.rb` runs with the same code, database, file,
and environment access as the Rails process.

Integrity checks prove which package was installed. They do not make unreviewed
Ruby safe.

## Package contract

A package is a ZIP with this layout:

```text
mcweb_plugin.yml       # required, exactly once, at the archive root
mcweb_package.yml      # optional host compatibility metadata
plugin.rb              # the manifest entrypoint
db/setup.rb            # optional versioned setup lifecycle
config/settings.yml    # optional strict settings schema and migrations
config/jobs.yml        # optional owned background-job declarations
...                    # plugin-owned Ruby and assets
```

The normal `mcweb_plugin.yml` rules still apply:

- IDs use `vendor/name`.
- Plugin versions use SemVer.
- `api_version` must be supported by this McWeb release.
- `requires` contains plugin IDs and RubyGems version requirements.
- The entrypoint must be a relative `.rb` file inside the package.
- Optional `setup` must also name a relative package-local `.rb` file.

Marketplace extraction additionally rejects:

- absolute paths, `..`, backslashes, NUL bytes, NTFS alternate-stream names,
  Windows device names, trailing spaces/dots, and case/Unicode-normalized path
  collisions;
- symbolic links, unsupported ZIP entry types, `.git`, `.gitconfig`,
  `.git-credentials`, and `.gitmodules`;
- multiple or nested plugin manifests;
- archives, entries, expanded payloads, or compression ratios above the
  bounded limits in `PackageArchive`.

Files are extracted into a private staging directory and can only replace the
managed path derived from the validated plugin ID. A package cannot choose an
arbitrary destination or overwrite an occupied unrelated directory.

## Optional compatibility metadata

`mcweb_package.yml` is strict safe YAML:

```yaml
schema_version: "1"
plugin:
  id: acme/example
  version: 2.3.0
compatibility:
  plugin_api: "~> 1.0"
  ruby: ">= 4.0"
  rails: "~> 8.1"
```

The plugin ID and version must exactly match `mcweb_plugin.yml`. Compatibility
values use RubyGems requirement syntax and are checked before any package file
is activated. Unknown keys, aliases, duplicate keys, and invalid requirements
are rejected.

## Versioned setup lifecycle

A reviewed package may opt into database setup by adding one path to
`mcweb_plugin.yml`:

```yaml
setup: db/setup.rb
```

The path comes only from the extracted manifest. It cannot be supplied to a
Manager operation, must be a relative `.rb` path, must resolve to a regular
file, and must remain inside that exact package directory.

The setup file registers exactly one plan:

```ruby
Mcweb::Plugins::Marketplace::Setup.define do
  install_step "create_widgets" do |context|
    context.connection.create_table(:acme_widgets) do |table|
      table.string :name, null: false
      table.timestamps
    end
  end

  upgrade_step "add_widget_slug", to: "1.2.0" do |context|
    context.connection.add_column(:acme_widgets, :slug, :string)
  end

  teardown_step "drop_widgets" do |context|
    context.connection.drop_table(:acme_widgets, if_exists: true)
  end
end
```

`uninstall_step` and `teardown_step` are equivalent. Step IDs use a bounded
lowercase identifier grammar and must be unique across the complete plan.
Install and teardown steps run in declaration order. Upgrade steps whose target
is newer than the installed version and no newer than the candidate run by
target SemVer, then declaration order. A target newer than the containing
package is rejected.

Each callback receives a frozen context with `plugin_id`, `phase`, `step_id`,
`from_version`, `to_version`, `target_version`, `operation_id`, and the current
Active Record `connection`. Completed version and step IDs are persisted in the
Marketplace receipt. A completed ID is skipped if execution is retried.
Reinstalling after a completed uninstall starts a new install lifecycle.

Setup code is fully trusted Ruby, not a sandbox. Shape and path checks prevent
accidental or client-selected registration, but they do not restrict what an
approved callback can do. Database changes must use the supplied connection.
External I/O cannot be rolled back and should be idempotent or deferred until
after deployment.

## Source and digest policy

Every install requires:

- a local package path;
- provenance using an `https://` or `file://` URI;
- the expected lowercase or uppercase SHA-256 digest.

HTTPS credentials are rejected. Query strings and fragments are deliberately
removed before provenance is persisted, so temporary download tokens do not
enter Marketplace receipts or operation logs. Do not put credentials in URL
paths or inside packages.

This backend does not fetch remote URLs. Downloading, signature verification,
publisher approval, and calculating the expected digest belong to the trusted
release/deployment pipeline. Keeping download and execution as separate steps
also avoids turning Rails into a general network package fetcher.

## Atomic lifecycle and rollback

The manager holds a cross-process file lock for every mutation. Its plugin root
and state root must be on the same filesystem, allowing directory renames to be
the commit point.

For install and upgrade it:

1. verifies provenance and SHA-256;
2. safely extracts and validates both manifests;
3. checks API/runtime compatibility, direct dependencies, dependency cycles,
   reverse dependency constraints, and downgrade intent;
4. validates and loads the optional setup plan before activation;
5. moves the old version to a recovery backup, if present;
6. atomically moves the candidate into `plugins/vendor/name`;
7. runs install or ordered upgrade steps inside a new database transaction;
8. reloads the trusted plugin runtime and requires the candidate to become
   `active` or `degraded`;
9. writes the receipt, including completed setup state, before committing;
10. rolls back the database transaction, receipt, directory and runtime if any
    setup, reload, receipt, or commit operation fails.

`disable` moves a managed plugin outside the Loader's discovery root. `enable`
moves it back only after dependencies pass. `uninstall` moves the plugin into a
recoverable quarantine instead of deleting it. Uninstall runs teardown steps in
the same coordinated database/filesystem/runtime boundary. Disable and enable
never run setup or teardown hooks. Disabling or uninstalling a plugin required
by any installed plugin is refused.

Marketplace operations intentionally refuse to move deployment plugins that
are outside their canonical managed path. This prevents an admin typo from
turning lifecycle commands into arbitrary filesystem moves.

The rollback boundary covers setup database writes made through the operation's
transaction, package files, receipts, and the host runtime registry. It cannot
undo external side effects or database work deliberately moved to another
connection/thread. Plugin review should keep entrypoint registration
side-effect-free and setup callbacks database-focused and idempotent.

An optional `contributions.settings` file is parsed and validated during
runtime registration. An invalid or path-escaping schema therefore fails the
candidate reload and enters the normal package/runtime rollback boundary before
the candidate becomes active. Setting values themselves live in encrypted,
append-only host records keyed by plugin ID and `schema_version`; package
rollback does not delete or reinterpret them. Moving forward to a new schema is
an explicit admin or SDK migration, and moving the package back automatically
selects the preserved older schema namespace. Disable and recoverable uninstall
retain all setting versions.

An optional `contributions.jobs` file is also validated during runtime
registration. It must remain inside the package and declare only strict owned
job keys and closed scalar argument schemas; packages cannot declare a Ruby
class to place on the host queue. Invalid declarations, missing handlers, and
path escapes fail activation inside the normal rollback boundary.

Owned job-run records survive disable and recoverable uninstall. A queued
delivery whose owner is unavailable, or whose installed version/declaration no
longer matches, becomes `paused` without consuming a handler attempt. Before an
intentional uninstall, cancel pending runs where practical. Re-enabling the
exact compatible package permits an explicit resume; an incompatible upgrade
must cancel the old run and enqueue a new one instead of reinterpreting its
payload. Running Ruby cannot be interrupted by the lifecycle operation, so
handlers must use the stable run public ID for idempotent external effects.

## State and observability

The default state directory is `storage/plugin_marketplace`, outside the plugin
Loader's discovery root and ignored by Git. It contains:

```text
operations.jsonl       # started/succeeded/failed operation events
receipts/              # source, digest, version, state, setup progress, recovery
staging/               # private extraction workspace
backups/               # replaced versions retained for recovery
disabled/              # disabled plugins
quarantine/            # uninstalled plugins
failed/                # candidates retained after failed activation
marketplace.lock       # cross-process lifecycle lock
```

Operation messages are UTF-8 normalized and bounded. Status tolerates a damaged
receipt or installed manifest and reports it in `errors` instead of hiding the
rest of the catalog. Each plugin reports both its filesystem state and current
per-process runtime status, so an installed package that did not load is shown
as `not_loaded` instead of being mislabeled active.

Successful non-dry-run install, upgrade, enable, disable, rollback, recover,
and uninstall operations also synchronize a database catalog:

- `PluginRelease` retains the active, disabled, rollback, or uninstalled
  release identity, an allow-listed manifest descriptor, canonical manifest
  digest, verified package digest, health, and safe diagnostic codes.
- `PluginContribution` stores each normalized static contribution descriptor,
  its descriptor SHA-256, and a separate schema SHA-256 where a settings or UI
  schema exists. Runtime setting values and credentials are never copied.
- `PluginFile` stores package-relative paths, expected size/SHA-256, observed
  size/SHA-256, and per-file health. Absolute paths are rejected and are never
  returned by the admin API.

The catalog is synchronized only after the package, receipt, local runtime, and
runtime generation have succeeded. Validation-only (`dry_run`) operations never
write catalog rows.

Administrators with `system.plugins.diagnostics` can run **Reconcile catalog**
from Apps & extensions. Reconciliation is idempotent and read-only with respect
to plugin packages: it scans manifests, receipts, managed files, and runtime
state, then updates only the database inventory and writes an audit event. It
backfills plugins installed before the catalog migration. When a historical
receipt has no package digest, the row is explicitly marked `derived`; it is
not represented as a verified archive digest.

Receipt/file/runtime differences remain visible as bounded diagnostic codes.
Reconciliation does not silently repair those authoritative sources.
Diagnostic records contain plugin IDs and codes only—never absolute paths,
exception text, source URLs, secrets, or plugin setting values.

For production releases, set `MCWEB_PLUGIN_DIR` to the deployment-owned plugin
directory. Installing into a source checkout's default `plugins/` directory
will correctly appear as a working-tree change; Marketplace never stages or
commits those files.

## Rake interface

Install or upgrade a package:

```powershell
$env:PACKAGE = "C:\releases\acme-example-2.3.0.zip"
$env:SOURCE = "https://packages.example.com/acme/example/2.3.0.zip"
$env:SHA256 = "<reviewed 64-character SHA-256>"
$env:ID = "acme/example"
bundle exec rake plugins:marketplace:install
```

Downgrades are rejected unless the operator explicitly sets
`ALLOW_DOWNGRADE=1`.

Lifecycle and status commands:

```powershell
$env:ID = "acme/example"
bundle exec rake plugins:marketplace:disable
bundle exec rake plugins:marketplace:enable
bundle exec rake plugins:marketplace:status
```

Use `LIMIT` to bound returned operation records. Omit `ID` from `status` to see
the complete Marketplace catalog.

Uninstall is bound to the exact version and reviewed package checksum shown by
the current status response. Refresh status immediately before the destructive
operation:

```powershell
$env:ID = "acme/example"
$env:VERSION = "<current version from status>"
$env:SHA256 = "<current 64-character SHA-256 from status>"
bundle exec rake plugins:marketplace:uninstall
```

If the package changes before the lifecycle lock is acquired, Marketplace
rejects the stale request before loading or executing teardown code.

## Deliberate boundaries

The backend does not add a remote catalog, automatic package download,
publisher signatures, arbitrary setup paths, or destructive quarantine purge.
Complex host-wide migrations remain part of the reviewed McWeb deployment
process; package-owned schema/data changes may use the versioned setup contract
above.
