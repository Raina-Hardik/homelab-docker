# homelab justfile
# Run `just` or `just --list` to see all available recipes.
#
# Usage:
#   just init          — one-time setup: create Docker network + all host dirs
#   just up            — bring up all stacks (excluding extras)
#   just down          — bring down all stacks (excluding extras)
#   just up-<stack>    — bring up a single stack
#   just down-<stack>  — bring down a single stack
#   just logs-<stack>  — tail logs for a single stack
#   just up-extras     — bring up opt-in extras (Vaultwarden + n8n)
#   just ps            — show all running containers
#   just pull          — pull latest images for all stacks

set dotenv-load := true

# UID/GID are taken from whoever runs `just` — overrides any PUID/PGID in .env.
# This ensures host-mounted directories are always owned by the right user.
export PUID := `id -u`
export PGID := `id -g`

# ── Default ───────────────────────────────────────────────────────────────────

default:
    @just --list

# ── Init ──────────────────────────────────────────────────────────────────────

# One-time setup: create the Docker network and all required host-mount directories.
# Re-running is safe — mkdir -p and `docker network create ... || true` are idempotent.
init: _network _mkdirs
    @echo "Init complete. Fill in .env then run: just up"

_network:
    docker network create homelab 2>/dev/null || true

_mkdirs:
    mkdir -p \
        /mnt/docker/adguard/work \
        /mnt/docker/adguard/conf \
        /mnt/docker/caddy/data \
        /mnt/docker/caddy/config \
        /mnt/docker/gluetun \
        /mnt/docker/qbittorrent \
        /mnt/docker/downloads \
        /mnt/docker/media/tv \
        /mnt/docker/media/movies \
        /mnt/docker/jellyfin \
        /mnt/docker/sonarr \
        /mnt/docker/radarr \
        /mnt/docker/prowlarr \
        /mnt/docker/immich/upload \
        /mnt/docker/immich/model-cache \
        /mnt/docker/immich/db \
        /mnt/docker/nextcloud \
        /mnt/docker/nextcloud-db \
        /mnt/docker/gitea \
        /mnt/docker/gh-runner/config \
        /mnt/docker/gh-runner/work \
        /mnt/docker/beszel \
        /mnt/docker/uptime-kuma \
        /mnt/docker/authentik/db \
        /mnt/docker/authentik/redis \
        /mnt/docker/authentik/media \
        /mnt/docker/authentik/certs \
        /mnt/docker/authentik/templates \
        /mnt/docker/vaultwarden \
        /mnt/docker/n8n
    @echo "Host directories ready under /mnt/docker/"

# ── Full stack (excludes extras) ──────────────────────────────────────────────

# Bring up all stacks except extras
up: up-core up-media up-cloud up-dev up-obs up-auth
    @echo "All stacks up."

# Bring down all stacks except extras (reverse order to avoid dangling deps)
down: down-auth down-obs down-dev down-cloud down-media down-core
    @echo "All stacks down."

# ── Core ──────────────────────────────────────────────────────────────────────

up-core:
    docker compose -f core/docker-compose.yml up -d

down-core:
    docker compose -f core/docker-compose.yml down

logs-core:
    docker compose -f core/docker-compose.yml logs -f

# ── Media ─────────────────────────────────────────────────────────────────────

up-media:
    docker compose -f media/docker-compose.yml up -d

down-media:
    docker compose -f media/docker-compose.yml down

logs-media:
    docker compose -f media/docker-compose.yml logs -f

# ── Cloud ─────────────────────────────────────────────────────────────────────

up-cloud:
    docker compose -f cloud/docker-compose.yml up -d

down-cloud:
    docker compose -f cloud/docker-compose.yml down

logs-cloud:
    docker compose -f cloud/docker-compose.yml logs -f

# ── Dev ───────────────────────────────────────────────────────────────────────

up-dev:
    docker compose -f dev/docker-compose.yml up -d

down-dev:
    docker compose -f dev/docker-compose.yml down

logs-dev:
    docker compose -f dev/docker-compose.yml logs -f

# ── Obs ───────────────────────────────────────────────────────────────────────

up-obs:
    docker compose -f obs/docker-compose.yml up -d

down-obs:
    docker compose -f obs/docker-compose.yml down

logs-obs:
    docker compose -f obs/docker-compose.yml logs -f

# ── Auth ──────────────────────────────────────────────────────────────────────

up-auth:
    docker compose -f auth/docker-compose.yml up -d

down-auth:
    docker compose -f auth/docker-compose.yml down

logs-auth:
    docker compose -f auth/docker-compose.yml logs -f

# ── Extras (opt-in) ───────────────────────────────────────────────────────────

up-extras:
    docker compose -f extras/docker-compose.yml up -d

down-extras:
    docker compose -f extras/docker-compose.yml down

logs-extras:
    docker compose -f extras/docker-compose.yml logs -f

# ── Utilities ─────────────────────────────────────────────────────────────────

# Show all running containers across every stack
ps:
    docker ps --format "table {{{{.Names}}}}\t{{{{.Status}}}}\t{{{{.Ports}}}}"

# Pull latest images for all stacks (extras included)
pull:
    docker compose -f core/docker-compose.yml pull
    docker compose -f media/docker-compose.yml pull
    docker compose -f cloud/docker-compose.yml pull
    docker compose -f dev/docker-compose.yml pull
    docker compose -f obs/docker-compose.yml pull
    docker compose -f auth/docker-compose.yml pull
    docker compose -f extras/docker-compose.yml pull

# Restart a single service by name across all compose files
# Usage: just restart caddy
restart service:
    docker restart {{ service }}
