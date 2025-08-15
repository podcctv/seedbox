#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

prompt_for_port() {
  local host_port=$1
  local container_port=$2
  local port=$host_port
  while nc -z localhost "$port" >/dev/null 2>&1; do
    read -p "Port $port is in use. Enter a new port for $container_port: " port
  done
  echo "$port"
}

prepare_compose_with_port_prompts() {
  local src=$1
  local dest=$(mktemp)
  cp "$src" "$dest"
  while IFS= read -r line; do
    if [[ $line =~ \"([0-9]+):([0-9]+)\" ]]; then
      host_port="${BASH_REMATCH[1]}"
      container_port="${BASH_REMATCH[2]}"
      new_port=$(prompt_for_port "$host_port" "$container_port")
      if [ "$new_port" != "$host_port" ]; then
        sed -i "s/${host_port}:${container_port}/${new_port}:${container_port}/" "$dest"
      fi
    fi
  done < "$src"
  echo "$dest"
}

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
import sys, yaml
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
    web = next((host for name, host, _ in ports if name in ['gateway', 'bitmagnet-next-web']), None)
    if web:
        print(f"Web interface available at http://localhost:{web}")
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
export DATA_DIR

mkdir -p \
  "$DATA_DIR/redis" \
  "$DATA_DIR/app-postgres" \
  "$DATA_DIR/bitmagnet-postgres" \
  "$DATA_DIR/minio" \
  "$DATA_DIR/qbittorrent/config" \
  "$DATA_DIR/qbittorrent/downloads" \
  "$DATA_DIR/worker/inbox" \
  "$DATA_DIR/worker/outbox" \
  "$DATA_DIR/rclone"

# Deploy services
echo "Select deployment option:"
echo "1) server"
echo "2) transcode"
echo "3) both"
if [ -z "${DEPLOY_CHOICE}" ]; then
  if [ -t 0 ]; then
    read -p "Enter choice [1-3]: " choice
  else
    choice=1
  fi
else
  choice=${DEPLOY_CHOICE}
fi

case "$choice" in
  1)
    serve_compose=$(prepare_compose_with_port_prompts compose.serve.yml)
    docker compose --project-directory "$REPO_DIR" -f "$serve_compose" up -d
    display_ports "$serve_compose"
    rm "$serve_compose"
    ;;
  2)
    docker compose --project-directory "$REPO_DIR" -f compose.transcode.yml up -d
    display_ports compose.transcode.yml
    ;;
  3)
    serve_compose=$(prepare_compose_with_port_prompts compose.serve.yml)
    docker compose --project-directory "$REPO_DIR" -f "$serve_compose" -f compose.transcode.yml up -d
    display_ports "$serve_compose" compose.transcode.yml
    rm "$serve_compose"
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
