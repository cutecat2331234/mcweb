# AGENTS.md

## Cursor Cloud specific instructions

McWeb is a Ruby on Rails 8.1 modular monolith (Ruby 4.0.6, PostgreSQL 18, Redis/Sidekiq)
with an Inertia + Vue 3 + Vite frontend. Standard dev commands live in `README.md`
("开发环境" section) and `INSTALL.md`; the notes below only cover non-obvious,
environment-specific caveats for this cloud VM.

### Toolchain locations (non-obvious)
- Ruby 4.0.6 is managed by **rbenv** at `~/.rbenv` (initialized in `~/.bashrc`). Interactive
  shells get `ruby`/`bundle` automatically. Non-interactive scripts must add
  `~/.rbenv/bin` to `PATH` and run `eval "$(rbenv init - bash)"` first.
- Node is provided by **nvm** (`~/.nvm`). Non-interactive scripts must source
  `"$NVM_DIR/nvm.sh"` to get `npm`.
- The update script (auto-run on startup) already sets both up and runs `bundle install` + `npm ci`.

### Services are NOT auto-started (no systemd in this VM)
PostgreSQL and Redis are installed but must be started manually at the beginning of each
session (they are not managed by systemd here):

```bash
sudo redis-server --daemonize yes
sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/postgresql/18/main \
  -l /tmp/pg.log -o "-c config_file=/etc/postgresql/18/main/postgresql.conf" start
```

The `postgres` role password is `postgres` (connects over TCP `127.0.0.1:5432`).

### Local instance config
- `config/local.yml` (gitignored) holds the DB credentials, `secret_key_base`,
  `lockbox_master_key`, and `redis_url`. It is already generated and persists in the VM
  snapshot. `config/boot.rb` bridges it into `DATABASE_URL`/`REDIS_URL`. Do not commit it.
- Template storage in dev writes to `/var/lib/mcweb/templates` (created, owned by `ubuntu`).
  Override with `MCWEB_TEMPLATE_DIR` if needed. Seeding (`db:seed`) fails if this dir is not writable.

### Running the app
- `bin/dev` runs Puma (`:3000`), Vite dev (`:3036`), and the Tailwind watcher via Foreman.
- The app is already installed: the `/setup` wizard was completed with admin
  `admin@example.com` / `password123`. A fresh DB (dropped/recreated) will redirect to
  `/setup` again until the wizard is re-run.
- Background jobs use Sidekiq (`bin/jobs`), which needs Redis running. Browsing the app
  does not require the worker; async job processing does.

### Tests & lint
- Tests: build test assets first (the CI order), then run:
  `RAILS_ENV=test bundle exec rails tailwindcss:build && bin/vite build --mode=test && RAILS_ENV=test bin/rails db:prepare && bin/rails test`.
- Known brittle failure: `Round84WebhookDateFilterTest#test_store_webhook_index_filters_by_date_range`
  asserts the admin HTML body excludes the 3-char `order_public_id` `"old"`, but the page
  preloads a Vite asset named `icon-menu-unfold-*.js` ("unf**old**"), so the substring match
  fails. This is unrelated to environment setup; the rest of the suite passes.
- Lint: `bin/rubocop`. Security scans: `bin/brakeman`, `bin/bundler-audit`, `bin/importmap audit` (see `bin/ci`).
