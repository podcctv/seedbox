#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Example environment check: detect Windows systems
if uname | grep -qi "windows"; then
  echo "Detected Windows environment; this script targets Unix-like systems."
fi

CONFIG_FILE="$REPO_DIR/deploy.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

ensure_pyyaml() {
  python3 -c "import yaml" >/dev/null 2>&1 && return
  echo "PyYAML module not found. Attempting to install..." >&2
  if python3 -m pip install --user PyYAML >/dev/null 2>&1; then
    echo "PyYAML installed." >&2
  else
    echo "Failed to install PyYAML. Port information will not be displayed." >&2
    return 1
  fi
}

display_ports() {
  ensure_pyyaml || return
  python3 - "$@" <<'PY'
import sys, yaml, os
host_addr = os.environ.get("HOST_ADDR", "localhost")
ports = []
for file in sys.argv[1:]:
    with open(file) as f:
        data = yaml.safe_load(f)
    services = data.get("services", {}) or {}
    for name, svc in services.items():
        for mapping in svc.get("ports", []) or []:
            host, _, container = mapping.partition(":")
            ports.append((name, host, container))

if not ports:
    print("No services expose host ports.")
else:
    print("Service port mappings:")
    for name, host, container in ports:
        print(f"  {host} -> {name} (container {container})")
    web_services = ['web', 'gateway']
    web = next((host for svc in web_services for name, host, _ in ports if name == svc), None)
    if web:
        print(f"Web interface available at http://{host_addr}:{web}")
    else:
        print("No web interface exposed.")
    trans = next((host for name, host, _ in ports if name.startswith('worker') or 'transcode' in name), None)
    if trans:
        print(f"Connect to transcode server on port {trans}")
    else:
        print("Transcode services expose no ports.")
PY
}

# Update repository
if [ -d .git ]; then
  echo "Updating repository..."
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain)" ]; then
      echo "Stashing local changes..."
      git stash push --include-untracked
      STASHED=1
    fi
    git pull --rebase
    if [ "${STASHED:-0}" -eq 1 ]; then
      echo "Restoring local changes..."
      git stash pop || true
    fi
  else
    echo "No upstream configured for current branch. Skipping pull."
  fi
fi

echo "Select deployment option:"
echo "1) server"
echo "2) transcode"
echo "3) both"
echo "4) uninstall"
if [ -z "${DEPLOY_CHOICE}" ]; then
  if [ -t 0 ]; then
    read -p "Enter choice [1-4]: " choice
  else
    choice=1
  fi
else
  choice=${DEPLOY_CHOICE}
fi

# Prompt for persistent data directory. Allow preset DATA_DIR or non-interactive defaults.
if [ -z "${DATA_DIR}" ]; then
  if [ -t 0 ]; then
    read -p "Enter data directory [/opt/seedbox]: " DATA_DIR
    DATA_DIR=${DATA_DIR:-/opt/seedbox}
  else
    DATA_DIR=/opt/seedbox
  fi
fi

# Ensure the data directory is an absolute path for Docker volume mounts
if [[ "$DATA_DIR" != /* ]]; then
  DATA_DIR="/$DATA_DIR"
fi
export DATA_DIR

HOST_ADDR=$(hostname -I | awk '{print $1}')
export HOST_ADDR
export NEXT_PUBLIC_API_BASE_URL="http://${HOST_ADDR}:28000"

if [ "$choice" = "4" ]; then
  docker compose --project-directory "$REPO_DIR" -f compose.serve.yml -f compose.transcode.yml down
  exit 0
fi

# Configure external Bitmagnet Postgres connection
echo "Configure Bitmagnet Postgres connection:"
if [ -z "${BITMAGNET_DB_HOST}" ]; then
  if [ -t 0 ]; then
    echo "If Postgres runs in Docker on this machine, use a hostname reachable from containers (e.g., host.docker.internal)."
    read -p "Host: " BITMAGNET_DB_HOST
  else
    echo "BITMAGNET_DB_HOST is required." >&2
    exit 1
  fi
fi
if [ -z "${BITMAGNET_DB_PORT}" ]; then
  if [ -t 0 ]; then
    read -p "Port [5432]: " BITMAGNET_DB_PORT
    BITMAGNET_DB_PORT=${BITMAGNET_DB_PORT:-5432}
  else
    BITMAGNET_DB_PORT=5432
  fi
fi
if [ -z "${BITMAGNET_DB_USER}" ]; then
  if [ -t 0 ]; then
    read -p "Username: " BITMAGNET_DB_USER
  else
    echo "BITMAGNET_DB_USER is required." >&2
    exit 1
  fi
fi
if [ -z "${BITMAGNET_DB_PASS}" ]; then
  if [ -t 0 ]; then
    read -s -p "Password: " BITMAGNET_DB_PASS
    echo
  else
    echo "BITMAGNET_DB_PASS is required." >&2
    exit 1
  fi
fi
if [ -z "${BITMAGNET_DB_NAME}" ]; then
  if [ -t 0 ]; then
    read -p "Database [bitmagnet]: " BITMAGNET_DB_NAME
    BITMAGNET_DB_NAME=${BITMAGNET_DB_NAME:-bitmagnet}
  else
    BITMAGNET_DB_NAME=bitmagnet
  fi
fi

echo "Testing Bitmagnet Postgres connection..."
echo "Running test query: SELECT 1"
if ! docker run --rm -e PGPASSWORD="$BITMAGNET_DB_PASS" postgres:16-alpine \
  psql -h "$BITMAGNET_DB_HOST" -p "$BITMAGNET_DB_PORT" -U "$BITMAGNET_DB_USER" -d "$BITMAGNET_DB_NAME" -c "SELECT 1"; then
  echo "Failed to connect to Bitmagnet Postgres. Aborting." >&2
  exit 1
fi
echo "Bitmagnet Postgres connection successful."

echo "Running sample movie query..."
CONTENT_QUERY="SELECT id FROM public.content LIMIT 1;"
if ! docker run --rm -e PGPASSWORD="$BITMAGNET_DB_PASS" postgres:16-alpine \
  psql -h "$BITMAGNET_DB_HOST" -p "$BITMAGNET_DB_PORT" -U "$BITMAGNET_DB_USER" -d "$BITMAGNET_DB_NAME" -c "$CONTENT_QUERY"; then
  echo "Sample content query failed. Aborting." >&2
  exit 1
fi
echo "Sample content query successful."

echo "Running sample 1080P torrent query..."
TORRENT_QUERY="SELECT encode(info_hash, 'hex') AS id, name FROM public.torrents WHERE name ILIKE '%1080P%' LIMIT 1;"
TORRENT_RESULT=$(docker run --rm -e PGPASSWORD="$BITMAGNET_DB_PASS" postgres:16-alpine \
  psql -h "$BITMAGNET_DB_HOST" -p "$BITMAGNET_DB_PORT" -U "$BITMAGNET_DB_USER" -d "$BITMAGNET_DB_NAME" -t -A -c "$TORRENT_QUERY" | tr -d '[:space:]')
if [ -z "$TORRENT_RESULT" ]; then
  echo "1080P torrent query returned no results. Aborting." >&2
  exit 1
fi
echo "Sample 1080P torrent query successful."
export BITMAGNET_RO_DSN="postgresql://${BITMAGNET_DB_USER}:${BITMAGNET_DB_PASS}@${BITMAGNET_DB_HOST}:${BITMAGNET_DB_PORT}/${BITMAGNET_DB_NAME}"

# Persist environment variables for docker compose
ENV_FILE="$REPO_DIR/.env"
cat > "$ENV_FILE" <<EOF
NEXT_PUBLIC_API_BASE_URL=$NEXT_PUBLIC_API_BASE_URL
BITMAGNET_RO_DSN=$BITMAGNET_RO_DSN
DATA_DIR=$DATA_DIR
EOF

mkdir -p \
  "$DATA_DIR/app-postgres" \
  "$DATA_DIR/minio" \
  "$DATA_DIR/qbittorrent/config" \
  "$DATA_DIR/qbittorrent/downloads" \
  "$DATA_DIR/worker/inbox" \
  "$DATA_DIR/worker/outbox" \
  "$DATA_DIR/rclone"

case "$choice" in
  1)
    docker compose --project-directory "$REPO_DIR" -f compose.serve.yml up -d
    display_ports compose.serve.yml
    ;;
  2)
    docker compose --project-directory "$REPO_DIR" -f compose.transcode.yml up -d
    display_ports compose.transcode.yml
    ;;
  3)
    docker compose --project-directory "$REPO_DIR" -f compose.serve.yml -f compose.transcode.yml up -d
    display_ports compose.serve.yml compose.transcode.yml
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac

if [ ! -f "$CONFIG_FILE" ]; then
  {
    echo "BITMAGNET_DB_HOST=$BITMAGNET_DB_HOST"
    echo "BITMAGNET_DB_PORT=$BITMAGNET_DB_PORT"
    echo "BITMAGNET_DB_USER=$BITMAGNET_DB_USER"
    echo "BITMAGNET_DB_PASS=$BITMAGNET_DB_PASS"
    echo "BITMAGNET_DB_NAME=$BITMAGNET_DB_NAME"
  } > "$CONFIG_FILE"
fi
