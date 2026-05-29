# homelab-docker

Self-hosted homelab stack split into focused Docker Compose stacks and managed with `just`.

This document describes the current running architecture and how to operate it. It is intentionally not a changelog.

## What This Repo Runs

### Core
- AdGuard Home (DNS filtering)
- Caddy with Tailscale integration (reverse proxy + service-bound HTTPS certs)
- Homepage dashboard

### ARR
- Gluetun (VPN tunnel)
- qBittorrent (torrent client, traffic forced through Gluetun)
- Prowlarr (indexer aggregator)
- Sonarr (TV show automation)
- Radarr (movie automation)
- Lidarr (music automation)
- Tdarr (H.265/≤1080p re-encoder, Intel iGPU-accelerated via VA-API)

### Media
- Jellyfin (media server)
- Seanime (hardware-accelerated anime client/server)
- Navidrome (music server)
- Feishin (music player UI for Navidrome)

### Cloud
- AFFiNE (documentation/workspace)
- Immich server
- Immich machine learning
- Immich PostgreSQL (pgvecto-rs)
- Immich Redis
- Nextcloud
- Nextcloud MariaDB

### Backup
- Zerobyte (restic control plane)

### Dev
- Forgejo (running in service/container `gitea`)
- GitHub Actions self-hosted runner (profile-based, opt-in)

### Obs
- Beszel hub
- Beszel agent (host network)
- Dozzle
- Uptime Kuma

### Auth
- Pocket ID

### Extras (opt-in)
- Vaultwarden
- n8n

### Games
- Minecraft PaperMC (2-player survival server, autopause when idle)

## Repository Layout

```text
.
|-- auth/
|   `-- docker-compose.yml
|-- backup/
|   `-- docker-compose.yml
|-- arr/
|   `-- docker-compose.yml
|-- cloud/
|   `-- docker-compose.yml
|-- core/
|   |-- Caddyfile
|   `-- docker-compose.yml
|-- dev/
|   `-- docker-compose.yml
|-- extras/
|   `-- docker-compose.yml
|-- games/
|   `-- docker-compose.yml
|-- media/
|   |-- docker-compose.yml
|   `-- seanime.config.toml
|-- obs/
|   `-- docker-compose.yml
|-- .env.example
|-- justfile
`-- README.md
```

## Prerequisites

- Docker Engine with Compose v2 (`docker compose`)
- `just` command runner
- Tailscale running on the host (not managed in this repo)
- Linux host capabilities used by some services:
  - `/var/run/tailscale/tailscaled.sock` mounted into Caddy
  - `/dev/net/tun` for Gluetun
  - `/dev/dri` for Jellyfin/Seanime/Tdarr hardware acceleration (Intel iGPU / VA-API)

## First-Time Setup

1. Copy environment template:

```bash
cp .env.example .env
```

2. Fill in required values in `.env`.

3. Initialize network and bind-mount directories:

```bash
just init
```

4. Pull images (recommended):

```bash
just pull
```

5. Start default stacks (everything except extras and runner):

```bash
just up
```

## Day-to-Day Commands

```bash
# Per-stack lifecycle
just up-core      && just down-core
just up-arr       && just down-arr
just up-media     && just down-media
just up-cloud     && just down-cloud
just up-backup    && just down-backup
just up-dev       && just down-dev
just up-obs       && just down-obs
just up-auth      && just down-auth
just up-games     && just down-games
just up-extras    && just down-extras

# Logs
just logs-core
just logs-arr
just logs-media
just logs-cloud
just logs-backup
just logs-dev
just logs-obs
just logs-auth
just logs-games
just logs-extras

# Utilities
just ps
just pull
just restart <container-name>
```

Runner is separate from `just up`:

```bash
just up-runner
just down-runner
just logs-runner
```

## Routing and Access

Caddy routes services on Tailscale subdomains under `TS_DOMAIN`.

Common endpoints:
- `https://home.<TS_DOMAIN>` (Homepage)
- `https://adguard.<TS_DOMAIN>`
- `https://qbit.<TS_DOMAIN>`
- `https://prowlarr.<TS_DOMAIN>`
- `https://sonarr.<TS_DOMAIN>`
- `https://radarr.<TS_DOMAIN>`
- `https://lidarr.<TS_DOMAIN>`
- `https://tdarr.<TS_DOMAIN>`
- `https://jellyfin.<TS_DOMAIN>`
- `https://anime.<TS_DOMAIN>`
- `https://navidrome.<TS_DOMAIN>`
- `https://feishin.<TS_DOMAIN>`
- `https://immich.<TS_DOMAIN>`
- `https://affine.<TS_DOMAIN>`
- `https://nextcloud.<TS_DOMAIN>`
- `https://backup.<TS_DOMAIN>`
- `https://gitea.<TS_DOMAIN>`
- `https://beszel.<TS_DOMAIN>`
- `https://dozzle.<TS_DOMAIN>`
- `https://uptime.<TS_DOMAIN>`
- `https://pocketid.<TS_DOMAIN>`

Extras routes are defined but commented in `core/Caddyfile`:
- `vault.<TS_DOMAIN>`
- `n8n.<TS_DOMAIN>`

## Networking Model

- All compose stacks use the shared external Docker network: `homelab`
- **Port binding strategy**: Web UIs are NOT exposed to the host. All services are accessed through Caddy reverse proxy via Tailscale HTTPS.
  - Exception: `DNS` (AdGuard on 53/tcp+udp) — system-level DNS requirement
  - Exception: Torrent protocol ports (Gluetun on 6881/tcp+udp) — required for DHT peer connectivity
  - Exception: Forgejo SSH (host `2222`) — optional, can be replaced with Tailscale SSH
  - Exception: Tdarr server port (8266) — required for external node connectivity
  - Exception: Minecraft (25565/tcp) — game protocol, direct TCP, no HTTP proxy
- qBittorrent uses `network_mode: service:gluetun` (no independent network)
- Prowlarr is also routed through Gluetun
- Beszel agent runs on host networking (`0.0.0.0:45876`)
- Beszel hub is accessed via Caddy (`beszel.<TS_DOMAIN>`)

## Storage Model

All persistent data is bind-mounted under:
- `${HOST_MOUNT_ROOT:-/mnt/docker}`

`just init` creates expected directories automatically.

## Environment Variables

Use `.env.example` as the source of truth. Important groups:

- System: `TZ`, `PUID`, `PGID`, `HOST_MOUNT_ROOT`
- Core/Tailscale/Caddy: `TS_DOMAIN`, `TS_AUTHKEY`, `TS_TAG`, `ACME_EMAIL`, `LOCAL_DOMAIN`
- ARR VPN: `VPN_*`, `OPENVPN_USER`, `OPENVPN_PASSWORD`
- Cloud: `IMMICH_DB_PASSWORD`, `REDIS_PASSWORD`, `NEXTCLOUD_*`
- Cloud: `ONLYOFFICE_JWT_SECRET`, `JWT_HEADER`
- Backup: `ZEROBYTE_APP_SECRET`
- Obs: `BESZEL_KEY`
- Auth: `ENCRYPTION_KEY`
- Runner: `GITHUB_RUNNER_TOKEN`, `GITHUB_RUNNER_REPO`, `GITHUB_RUNNER_NAME`
- Extras: `VAULTWARDEN_ADMIN_TOKEN`, `N8N_BASIC_AUTH_*`, `N8N_ENCRYPTION_KEY`

## Post-Boot Actions

Some services need UI-driven setup after containers are healthy:

- AdGuard Home: complete first-run setup via `https://adguard.<TS_DOMAIN>` (Caddy routing)
- Beszel: add system in Hub UI at `https://beszel.<TS_DOMAIN>` and set `BESZEL_KEY`, then rerun `just up-obs`
- Nextcloud OnlyOffice: install/enable the OnlyOffice app in Nextcloud, set the document server URL to `http://onlyoffice/`, and use `ONLYOFFICE_JWT_SECRET` with header `Authorization`
- Pocket ID: configure providers/apps/policies via `https://pocketid.<TS_DOMAIN>`
- Uptime Kuma: create monitors in UI at `https://uptime.<TS_DOMAIN>`
- Tdarr: create a Flow at `https://tdarr.<TS_DOMAIN>` that (1) transcodes to H.265 using the `hevc_vaapi` encoder and (2) scales to ≤1080p. Add your media libraries pointing to `/media/tv`, `/media/movies`, `/media/anime`, `/media/music`.
- Runner: generate a fresh GitHub runner registration token, set env vars, run `just up-runner`

## Notes

- Homepage host allow-list is set to `home.<TS_DOMAIN>`
- Seanime config is tracked in `media/seanime.config.toml` and mounted into container
- Seanime tracked config currently includes default password `admin`; change it for real deployments
- All service UIs are accessed via Tailscale subdomains. Caddy handles reverse proxy routing with automatic HTTPS via Tailscale certificates.
- Healthchecks are defined across all stacks and used by `depends_on: condition: service_healthy` where needed
