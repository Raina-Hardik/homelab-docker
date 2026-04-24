# homelab

A quick, reproducible setup for my personal homelab. Not an exhaustive list — just the things that make life fun and easy to have.

Each stack lives in its own Docker Compose file. Custom images (where needed) use a `Dockerfile.service` in the same directory. Everything is bootstrapped and operated via a `justfile`.

> **Not managed here:** Tailscale runs directly on the host. It provides the VPN tunnel, SSH access, and LAN routing. Docker never touches it.

---

## Philosophy

- **Dedicated compose file per stack** — bring up only what you need, independently
- **Host-mounted storage** — all persistent data lives under `/mnt/docker/<service>`, no named volumes
- **UID/GID passthrough** — every service runs as the invoking user's UID/GID, sourced at `just` runtime, no permission errors ever
- **`.env` for all config and secrets** — `.env.example` documents every required variable including timezone
- **`just` for everything** — one recipe to bring up the full stack, or granular per-stack control
- **Extras are opt-in** — the default `just up` does not boot extras; they have their own explicit recipes

---

## Repository Structure

```
homelab/
├── core/
│   ├── docker-compose.yml      # AdGuard Home + Caddy
│   └── Caddyfile               # Static reverse proxy config (uses env vars)
├── media/
│   └── docker-compose.yml      # Jellyfin + Sonarr + Radarr + Prowlarr + qBittorrent + Gluetun
├── cloud/
│   └── docker-compose.yml      # Immich + Nextcloud
├── dev/
│   └── docker-compose.yml      # Gitea + GitHub Actions Runner
├── obs/
│   └── docker-compose.yml      # Beszel + Dozzle + Uptime Kuma
├── auth/
│   └── docker-compose.yml      # Authentik
├── extras/
│   └── docker-compose.yml      # Vaultwarden + n8n
├── .env                        # Your actual secrets (gitignored)
├── .env.example                # Template — copy to .env and fill in
├── .gitignore
└── justfile
```

---

## Stacks

### Core
| Service | Role |
|---------|------|
| AdGuard Home | Network-wide DNS with ad blocking |
| Caddy | Reverse proxy with automatic HTTPS via env-injected domain config |

### Media
| Service | Role |
|---------|------|
| Jellyfin | Media server |
| Sonarr | TV show automation |
| Radarr | Movie automation |
| Prowlarr | Indexer manager — feeds Sonarr and Radarr |
| qBittorrent | Torrent client — network routed through Gluetun |
| Gluetun | ProtonVPN tunnel — all qBittorrent traffic exits here |

### Cloud
| Service | Role |
|---------|------|
| Immich | Self-hosted photo and video backup (Google Photos replacement) |
| Nextcloud | Self-hosted file sync and collaboration (Google Drive replacement) |

### Dev
| Service | Role |
|---------|------|
| Gitea | Self-hosted Git forge |
| GitHub Actions Runner | Personal self-hosted CI runner for GitHub repos (e.g. building images, pushing to ECS) |

### Obs
| Service | Role |
|---------|------|
| Beszel | Host and container metrics — lightweight agent-based hub with a clean UI |
| Dozzle | Real-time Docker log viewer — no storage, just live tailing |
| Uptime Kuma | External uptime monitoring — pings services and alerts when they go down |

### Auth
| Service | Role |
|---------|------|
| Authentik | Identity provider and SSO — configure integrations manually after boot |

### Extras *(opt-in only)*
| Service | Role |
|---------|------|
| Vaultwarden | Self-hosted Bitwarden-compatible password manager |
| n8n | Workflow automation |

---

## Network & Storage

### Docker Network

All stacks share a single external Docker bridge network called `homelab`. This allows Caddy (in the `core` stack) to reach services in any other stack by container name.

**Exception:** qBittorrent uses `network_mode: service:gluetun` — its traffic exits entirely through the Gluetun VPN container.

### Host Storage

All persistent data is host-mounted under `/mnt/docker/`. The `justfile` runs `mkdir -p` for every required path before any stack boots.

```
/mnt/docker/
├── adguard/
├── caddy/
├── jellyfin/
├── sonarr/
├── radarr/
├── prowlarr/
├── qbittorrent/
├── gluetun/
├── immich/
├── nextcloud/
├── gitea/
├── gh-runner/
├── beszel/
├── uptime-kuma/
├── authentik/
├── vaultwarden/
└── n8n/
```

Directories are created with ownership set to the UID/GID of the user running `just`. Services are configured with the same UID/GID via `PUID`/`PGID` in `.env`.

---

## Flow

### Traffic

```mermaid
flowchart TD
    Internet((Internet))
    Tailscale["Tailscale\n(host — not managed here)"]
    Caddy["Caddy\nReverse Proxy\n:80 / :443"]

    Internet -->|VPN tunnel| Tailscale
    Internet -->|HTTPS| Caddy

    Caddy --> AdGuard[AdGuard Home]
    Caddy --> Jellyfin
    Caddy --> Immich
    Caddy --> Nextcloud
    Caddy --> Gitea
    Caddy --> Beszel
    Caddy --> Dozzle
    Caddy --> UptimeKuma[Uptime Kuma]
    Caddy --> Authentik
    Caddy -.->|opt-in| Extras["Vaultwarden\nn8n"]
```

### Media Pipeline

```mermaid
flowchart LR
    Prowlarr -->|feed indexers| Sonarr
    Prowlarr -->|feed indexers| Radarr
    Sonarr -->|grab| qBittorrent
    Radarr -->|grab| qBittorrent
    qBittorrent -->|all traffic| Gluetun["Gluetun\nProtonVPN"]
    Gluetun --> Internet((Internet))
    qBittorrent -->|completed files| Jellyfin
```

---

## Quickstart

```bash
# 1. Clone and enter
git clone <repo> homelab && cd homelab

# 2. Set up your environment
cp .env.example .env
$EDITOR .env

# 3. Create the Docker network (once)
docker network create homelab

# 4. Bring up everything (excludes extras)
just up

# 5. Or bring up individual stacks
just up-core
just up-media
just up-cloud
just up-dev
just up-obs
just up-auth

# Extras are always explicit
just up-extras

# Tear down
just down
just down-core   # etc.
```

---

## Caddyfile & Domains

The `Caddyfile` is checked into the repo but contains **no hardcoded hostnames**. All domain names are injected via environment variables at runtime:

```
{env.TS_DOMAIN}        # your Tailscale machine hostname (e.g. myserver.tail1234.ts.net)
{env.LOCAL_DOMAIN}     # your local domain if you have one (e.g. home.internal)
```

These are set in `.env` which is gitignored. `.env.example` shows the expected format.

---

## Environment Variables

All configuration lives in `.env`. Never commit this file. Copy `.env.example` to get started:

```bash
cp .env.example .env
```

See `.env.example` for the full list. Key categories:

| Category | Variables |
|----------|-----------|
| System | `TZ`, `PUID`, `PGID` |
| Domains | `TS_DOMAIN`, `LOCAL_DOMAIN` |
| VPN | `VPN_SERVICE_PROVIDER`, `VPN_TYPE`, `OPENVPN_USER`, `OPENVPN_PASSWORD` |
| Immich | `DB_PASSWORD`, `REDIS_PASSWORD` |
| Nextcloud | `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` |
| Authentik | `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_POSTGRES_PASSWORD` |
| GitHub Runner | `GITHUB_RUNNER_TOKEN`, `GITHUB_RUNNER_REPO` |

---

## Requirements

- Docker Engine with Compose v2 (`docker compose`)
- [`just`](https://github.com/casey/just) — command runner
- Tailscale installed, authenticated, and running on the host
