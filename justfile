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
host_mount_root := env('HOST_MOUNT_ROOT', './mnt/docker')

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
        {{host_mount_root}}/adguard/work \
        {{host_mount_root}}/adguard/conf \
        {{host_mount_root}}/caddy/data \
        {{host_mount_root}}/caddy/config \
        {{host_mount_root}}/gluetun \
        {{host_mount_root}}/qbittorrent \
        {{host_mount_root}}/downloads \
        {{host_mount_root}}/media/tv \
        {{host_mount_root}}/media/movies \
        {{host_mount_root}}/jellyfin \
        {{host_mount_root}}/sonarr \
        {{host_mount_root}}/radarr \
        {{host_mount_root}}/prowlarr \
        {{host_mount_root}}/immich/upload \
        {{host_mount_root}}/immich/model-cache \
        {{host_mount_root}}/immich/db \
        {{host_mount_root}}/nextcloud \
        {{host_mount_root}}/nextcloud-db \
        {{host_mount_root}}/gitea \
        {{host_mount_root}}/gh-runner/config \
        {{host_mount_root}}/gh-runner/work \
        {{host_mount_root}}/beszel \
        {{host_mount_root}}/uptime-kuma \
        {{host_mount_root}}/authentik/db \
        {{host_mount_root}}/authentik/redis \
        {{host_mount_root}}/authentik/media \
        {{host_mount_root}}/authentik/certs \
        {{host_mount_root}}/authentik/templates \
        {{host_mount_root}}/vaultwarden \
        {{host_mount_root}}/n8n
    @echo "Host directories ready under {{host_mount_root}}/"

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

# ── GitHub Runner (opt-in profile under dev stack) ───────────────────────────

up-runner:
    docker compose -f dev/docker-compose.yml --profile runner up -d gh-runner

down-runner:
    docker compose -f dev/docker-compose.yml --profile runner rm -sf gh-runner

logs-runner:
    docker compose -f dev/docker-compose.yml --profile runner logs -f gh-runner

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
