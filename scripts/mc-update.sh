#!/usr/bin/env bash
# mc-update: check the Minecraft stack (Paper pin + plugins) against upstream and
# update it. Run it on the host that runs the container.
#
#   scripts/mc-update.sh            interactive (gum)
#   scripts/mc-update.sh --check    report only, change nothing
#   scripts/mc-update.sh --yes      apply plugin updates for the pinned Paper
#                                   version without prompting (never bumps Paper)
#   --no-restart                    leave the container alone after changes
#
# Nothing here is host-specific. The repo is located from this script's own
# path; the container, its data directory and the Paper pin come from the
# compose file, and the live data mount from `docker inspect`.
#
# Overrides (mainly for testing): MC_COMPOSE_FILE, MC_ENV_FILE, MC_DATA_DIR.
#
# Sources: Paper builds from fill.papermc.io, plugins from Modrinth. A plugin is
# managed when its jar's plugin.yml name matches a Modrinth project slug
# (lowercased); anything else is reported as unmanaged and left alone.

set -euo pipefail

UA="homelab-docker-mc-update/1.0"
MR_API="https://api.modrinth.com/v2"
PAPER_API="https://fill.papermc.io/v3/projects/paper"
LOADERS='["paper","spigot","bukkit"]'

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SELF_DIR/.." && pwd)
COMPOSE=${MC_COMPOSE_FILE:-$ROOT/games/docker-compose.yml}
ENV_FILE=${MC_ENV_FILE:-$ROOT/.env}

MODE=interactive
RESTART=yes
for arg in "$@"; do
    case $arg in
        --check) MODE=check ;;
        --yes) MODE=yes ;;
        --no-restart) RESTART=no ;;
        -h | --help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ── helpers ───────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }
say() { echo "$*"; }

for cmd in curl jq unzip docker gum; do
    command -v "$cmd" >/dev/null || die "missing dependency: $cmd"
done
[[ -f $COMPOSE ]] || die "compose file not found: $COMPOSE"

if [[ $MODE == interactive && ! -t 0 ]]; then
    die "interactive mode needs a terminal; use --check or --yes"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

get() { curl -fsS -A "$UA" "$@"; }

dc() {
    local envargs=()
    [[ -f $ENV_FILE ]] && envargs=(--env-file "$ENV_FILE")
    docker compose "${envargs[@]}" -f "$COMPOSE" "$@"
}

# ── discover the stack from the compose file ──────────────────────────────────

CONF=$(dc config --format json 2>/dev/null) || die "could not read $COMPOSE"
SERVICE=$(jq -r '[.services | to_entries[] | select(.value.image | test("itzg/minecraft-server"))][0].key // empty' <<<"$CONF")
[[ -n $SERVICE ]] || die "no itzg/minecraft-server service in $COMPOSE"
CONTAINER=$(jq -r --arg s "$SERVICE" '.services[$s].container_name // $s' <<<"$CONF")
PINNED=$(jq -r --arg s "$SERVICE" '.services[$s].environment.VERSION // "LATEST"' <<<"$CONF")

if [[ -n ${MC_DATA_DIR:-} ]]; then
    DATA=$MC_DATA_DIR
else
    DATA=$(docker inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)
    [[ -n $DATA ]] || DATA=$(jq -r --arg s "$SERVICE" '[.services[$s].volumes[] | select(.target == "/data")][0].source // empty' <<<"$CONF")
fi
[[ -d $DATA/plugins ]] || die "no plugins directory under '$DATA' (set MC_DATA_DIR?)"

# ── upstream lookups ──────────────────────────────────────────────────────────

# Stable Minecraft versions Paper builds, newest first.
paper_versions() {
    get "$PAPER_API" | jq -r '.versions | to_entries | map(.value[]) | .[] | select(test("^[0-9]+(\\.[0-9]+)*$"))'
}

# Newest Modrinth release of a project for a Minecraft version, as one JSON line
# {version,url,sha512,filename}, or nothing.
best_release() {
    local slug=$1 mc=$2
    get -G "$MR_API/project/$slug/version" \
        --data-urlencode "loaders=$LOADERS" \
        --data-urlencode "game_versions=[\"$mc\"]" 2>/dev/null |
        jq -c '[.[] | select(.version_type == "release")][0]
               | select(. != null)
               | (.files | (map(select(.primary))[0] // .[0])) as $f
               | {version: .version_number, url: $f.url, sha512: $f.hashes.sha512, filename: $f.filename}' || true
}

project_exists() { get "$MR_API/project/$1" >/dev/null 2>&1; }

# ── installed plugins ─────────────────────────────────────────────────────────

meta_field() { # jar field
    { unzip -p "$1" plugin.yml 2>/dev/null || unzip -p "$1" paper-plugin.yml 2>/dev/null || true; } |
        sed -n -E "s/^$2:[[:space:]]*['\"]?([^'\"]*)['\"]?[[:space:]]*\$/\1/p" | head -1
}

PL_JAR=() PL_NAME=() PL_VER=() PL_SLUG=()
UNMANAGED=()
shopt -s nullglob
for jar in "$DATA"/plugins/*.jar; do
    name=$(meta_field "$jar" name)
    ver=$(meta_field "$jar" version)
    if [[ -z $name ]]; then
        UNMANAGED+=("$(basename "$jar") (no plugin.yml)")
        continue
    fi
    slug=${name,,}
    if project_exists "$slug"; then
        PL_JAR+=("$jar") PL_NAME+=("$name") PL_VER+=("$ver") PL_SLUG+=("$slug")
    else
        UNMANAGED+=("$name $ver (no Modrinth project '$slug')")
    fi
done
shopt -u nullglob

norm() { local v=${1%%+*}; echo "${v%-SNAPSHOT}"; }

# True when $1 is a strictly older version than $2.
is_older() {
    local a b
    a=$(norm "$1") b=$(norm "$2")
    [[ $a != "$b" && $(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1) == "$a" ]]
}

# ── compatibility ─────────────────────────────────────────────────────────────

mapfile -t MC_VERSIONS < <(paper_versions)
[[ ${#MC_VERSIONS[@]} -gt 0 ]] || die "could not list Paper versions"
LATEST_MC=${MC_VERSIONS[0]}
TARGET=$PINNED
[[ $TARGET == LATEST ]] && TARGET=$LATEST_MC

# Newest Minecraft version that every managed plugin has a release for, looking
# only at versions newer than the pin.
BUMP_TO=""
for v in "${MC_VERSIONS[@]}"; do
    [[ $v == "$TARGET" ]] && break
    ok=yes
    for i in "${!PL_SLUG[@]}"; do
        [[ -n $(best_release "${PL_SLUG[$i]}" "$v") ]] || { ok=no; break; }
    done
    if [[ $ok == yes ]]; then BUMP_TO=$v; break; fi
done

# ── report ────────────────────────────────────────────────────────────────────

REL=()      # JSON per plugin for TARGET, or empty
ACT_IDX=()  # indexes of plugins that can be updated
rows=("Component,Installed,Available for $TARGET,Status")
for i in "${!PL_SLUG[@]}"; do
    r=$(best_release "${PL_SLUG[$i]}" "$TARGET")
    REL[i]=$r
    if [[ -z $r ]]; then
        rows+=("${PL_NAME[$i]},${PL_VER[$i]},-,no release for $TARGET")
        continue
    fi
    avail=$(jq -r .version <<<"$r")
    if is_older "${PL_VER[$i]}" "$avail"; then
        rows+=("${PL_NAME[$i]},${PL_VER[$i]},$avail,update available")
        ACT_IDX+=("$i")
    elif [[ $(norm "${PL_VER[$i]}") == "$(norm "$avail")" ]]; then
        rows+=("${PL_NAME[$i]},${PL_VER[$i]},$avail,up to date")
    else
        rows+=("${PL_NAME[$i]},${PL_VER[$i]},$avail,newer than the $TARGET build")
    fi
done
paper_status="latest is $LATEST_MC"
[[ $TARGET == "$LATEST_MC" ]] && paper_status="up to date"
[[ -n $BUMP_TO ]] && paper_status="$paper_status; all plugins support $BUMP_TO"
rows+=("Paper,$PINNED,$LATEST_MC,$paper_status")

echo
printf '%s\n' "${rows[@]}" | gum table --print --separator "," --border rounded
for u in "${UNMANAGED[@]}"; do say "unmanaged: $u"; done
echo

# ── choose what to do ─────────────────────────────────────────────────────────

DO_BUMP=no
DO_PLUGINS=()
case $MODE in
    check)
        exit 0
        ;;
    yes)
        DO_PLUGINS=("${ACT_IDX[@]}")
        ;;
    interactive)
        labels=() preselect=()
        for i in "${ACT_IDX[@]}"; do
            l="Update ${PL_NAME[$i]} ${PL_VER[$i]} -> $(jq -r .version <<<"${REL[$i]}")"
            labels+=("$l") preselect+=("$l")
        done
        bump_label=""
        if [[ -n $BUMP_TO ]]; then
            bump_label="Bump Paper $PINNED -> $BUMP_TO (and move every plugin to $BUMP_TO builds)"
            labels+=("$bump_label")
        fi
        if [[ ${#labels[@]} -eq 0 ]]; then
            say "Nothing to do."
            exit 0
        fi
        sel_arg=()
        if [[ ${#preselect[@]} -gt 0 ]]; then
            sel_arg=(--selected "$(IFS=,; echo "${preselect[*]}")")
        fi
        mapfile -t chosen < <(gum choose --no-limit "${sel_arg[@]}" --header "Space to toggle, enter to apply" "${labels[@]}")
        [[ ${#chosen[@]} -gt 0 ]] || { say "Nothing selected."; exit 0; }
        for c in "${chosen[@]}"; do
            if [[ -n $bump_label && $c == "$bump_label" ]]; then
                DO_BUMP=yes
                continue
            fi
            for i in "${ACT_IDX[@]}"; do
                [[ $c == "Update ${PL_NAME[$i]} ${PL_VER[$i]} -> "* ]] && DO_PLUGINS+=("$i")
            done
        done
        if [[ $DO_BUMP == yes ]]; then
            gum confirm "Worlds are upgraded in place when the server starts on $BUMP_TO and can't be rolled back. Back them up first. Continue?" || exit 1
        fi
        ;;
esac

# A bump moves every managed plugin to its build for the new version.
if [[ $DO_BUMP == yes ]]; then
    TARGET=$BUMP_TO
    DO_PLUGINS=()
    for i in "${!PL_SLUG[@]}"; do
        r=$(best_release "${PL_SLUG[$i]}" "$TARGET")
        REL[i]=$r
        is_older "${PL_VER[$i]}" "$(jq -r .version <<<"$r")" && DO_PLUGINS+=("$i")
    done
fi

[[ ${#DO_PLUGINS[@]} -gt 0 || $DO_BUMP == yes ]] || { say "Nothing to apply."; exit 0; }

# ── apply ─────────────────────────────────────────────────────────────────────

BACKUP="$DATA/plugins-backup/$(date +%Y%m%d-%H%M%S)"
for i in "${DO_PLUGINS[@]}"; do
    r=${REL[$i]}
    url=$(jq -r .url <<<"$r") sha=$(jq -r .sha512 <<<"$r")
    fn=$(jq -r .filename <<<"$r") ver=$(jq -r .version <<<"$r")
    say "Downloading ${PL_NAME[$i]} $ver"
    get -L -o "$TMP/$fn" "$url"
    echo "$sha  $TMP/$fn" | sha512sum -c --quiet - || die "checksum mismatch for $fn"
    mkdir -p "$BACKUP"
    mv "${PL_JAR[$i]}" "$BACKUP/"
    install -m 0644 "$TMP/$fn" "$DATA/plugins/$fn"
    say "  installed $fn (old jar in $BACKUP)"
done

if [[ $DO_BUMP == yes ]]; then
    grep -qE "^[[:space:]]*- VERSION=" "$COMPOSE" || die "no '- VERSION=' line in $COMPOSE to update"
    sed -i -E "s/^([[:space:]]*- VERSION=).*/\1$BUMP_TO/" "$COMPOSE"
    say "Set VERSION=$BUMP_TO in $COMPOSE (commit it)."
fi

# ── restart and watch the start-up ────────────────────────────────────────────

if [[ $RESTART == no ]]; then
    if [[ $DO_BUMP == yes ]]; then
        say "Recreate the container to apply: just up-games (or docker compose -f $COMPOSE up -d $SERVICE)"
    else
        say "Restart the server to apply: docker restart $CONTAINER"
    fi
    exit 0
fi
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    say "Container $CONTAINER does not exist yet; bring the stack up to apply."
    exit 0
fi
if [[ $MODE == interactive ]]; then
    gum confirm "Restart $CONTAINER now?" || { say "Not restarted."; exit 0; }
fi

if [[ $DO_BUMP == yes ]]; then
    dc up -d "$SERVICE" >/dev/null
else
    docker restart "$CONTAINER" >/dev/null
fi

started=$(docker inspect "$CONTAINER" --format '{{.State.StartedAt}}')
say "Waiting for $CONTAINER to start..."
for _ in $(seq 1 60); do
    logs=$(docker logs --since "$started" "$CONTAINER" 2>&1 || true)
    if grep -qE 'Done \(' <<<"$logs"; then
        say "Server is up."
        exit 0
    fi
    if grep -qE 'Encountered an unexpected exception|This crash report has been saved' <<<"$logs"; then
        die "server crashed on start-up; roll back from $BACKUP (see docker logs $CONTAINER)"
    fi
    sleep 3
done
die "no 'Done' after 3 minutes; check docker logs $CONTAINER"
