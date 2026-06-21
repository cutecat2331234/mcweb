# McWeb Host Console (mcweb-hostd)

`mcweb-hostd` is a standalone Go binary that provides a server-rendered web panel and CLI for installing and operating McWeb on the host. It is fully separate from the Rails application.

## Two installation paths

| Path | Description |
|------|-------------|
| **With hostd** | Install hostd first, then complete the 7-step wizard in the panel or CLI. Site and admin setup run via `bin/hostd-finalize`. You do **not** need `/setup`. |
| **Without hostd** | Deploy McWeb manually (`bin/install`, release tarball, etc.), start services, then open **`/setup`** in the browser for the Rails wizard. |

## Quick start

```bash
# Install binary (example)
sudo install -m 755 mcweb-hostd /usr/local/bin/
sudo mkdir -p /etc/mcweb /var/log/mcweb/hostd/jobs
sudo cp host/mcweb-hostd/config/hostd.example.yml /etc/mcweb/hostd.yml
sudo cp config/templates/mcweb-hostd.service /etc/systemd/system/
sudo mcweb-hostd init
sudo systemctl enable --now mcweb-hostd
```

Open `http://your-server:8787`, sign in, and go to **Install**.

Default listen address: `:8787`. Put Caddy or Nginx in front for TLS on a separate hostname (recommended).

## Web pages

| Path | Purpose |
|------|---------|
| `/init` | First-time hostd admin setup |
| `/login` | Sign in |
| `/` | Dashboard (status, health, version) |
| `/install` | 7-step McWeb installation wizard |
| `/operations` | Start, stop, restart, check, update |
| `/settings` | Paths, deploy mode, release URL |

## CLI reference

```bash
mcweb-hostd serve [--listen :8787]
mcweb-hostd init
mcweb-hostd status
mcweb-hostd check
mcweb-hostd start [--web] [--worker] [--all] [--docker]
mcweb-hostd stop  [--web] [--worker] [--all] [--docker]
mcweb-hostd restart ...
mcweb-hostd update [--version vX]
mcweb-hostd logs [--web] [--worker] [-f]
mcweb-hostd install wizard
mcweb-hostd install native [--fresh] [--version vX]
mcweb-hostd install docker [--pull]
```

## Lifecycle operations

| Action | Native (systemd) | Docker |
|--------|------------------|--------|
| Start | `systemctl start mcweb-web mcweb-worker` | `docker compose start` |
| Stop | `systemctl stop …` | `compose stop` |
| Restart | `systemctl restart …` | `compose restart` |
| Check | `bin/doctor` + `/health/live` + `/health/ready` | same + `compose ps` |
| Update | release + `bin/update` | `compose pull && up -d` |

## `bin/hostd-finalize`

Called by hostd after deployment to configure the database, create the owner account, and lock installation:

```bash
sudo -u mcweb /opt/mcweb/current/bin/hostd-finalize --input /path/to/payload.json
```

JSON shape:

```json
{
  "database": { "host": "127.0.0.1", "port": 5432, "username": "mcweb", "password": "…" },
  "site": { "name": "My Site", "url": "https://example.com" },
  "admin": { "email": "admin@example.com", "username": "admin", "password": "secret" }
}
```

## Docker Compose stack

Files live in [`deploy/docker/`](../deploy/docker/). Copy to `/opt/mcweb/docker` on the server:

```bash
sudo cp -r deploy/docker /opt/mcweb/docker
cd /opt/mcweb/docker && cp .env.example .env
docker compose up -d
```

Then use hostd **Install** wizard steps 4–7 (database defaults match compose `.env`).

## Paths

| Path | Use |
|------|-----|
| `/etc/mcweb/hostd.yml` | Hostd configuration |
| `/etc/mcweb/mcweb.env` | McWeb Rails environment |
| `/etc/mcweb/installed_via_hostd` | Marker when installed through hostd |
| `/opt/mcweb/current` | McWeb application |
| `/var/lib/mcweb/plugins` | Future Ruby plugins (placeholder) |

## Phase 4 (optional)

- **Backup / restore**: calls `bin/backup` and `bin/restore` when present
- **mcweb-node**: documents installing the node agent binary and `mcweb-node.service`
- **Plugins**: creates `/var/lib/mcweb/plugins`; full boot loader is a separate project

## Security

- Hostd runs as **root** so it can manage systemd and Docker.
- Restrict port `:8787` with firewall rules; use TLS via reverse proxy.
- Hostd credentials are independent of McWeb admin accounts.
