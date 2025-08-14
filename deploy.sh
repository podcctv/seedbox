#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

find_free_port() {
  local port=$1
  while nc -z localhost "$port" >/dev/null 2>&1; do
    port=$((port+1))
  done
  echo "$port"
}

prepare_compose_with_free_ports() {
  local src=$1
  local dest=$(mktemp)
  cp "$src" "$dest"
  while IFS= read -r line; do
    if [[ $line =~ \"([0-9]+):([0-9]+)\" ]]; then
      host_port="${BASH_REMATCH[1]}"
      container_port="${BASH_REMATCH[2]}"
      free_port=$(find_free_port "$host_port")
      if [ "$free_port" != "$host_port" ]; then
        echo "Port $host_port is in use. Using $free_port instead." >&2
        sed -i "s/${host_port}:${container_port}/${free_port}:${container_port}/" "$dest"
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
    web = next((host for name, host, _ in ports if name == 'gateway'), None)
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

configure_env() {
  local template=".env.example"
  if [ ! -f "$template" ]; then
    if [ -f .env ]; then
      echo ".env.example not found. Using existing .env as template." >&2
      template=".env"
    else
      echo "No environment template found (missing .env.example or .env)." >&2
      return 1
    fi
  fi

  local tmp=$(mktemp)
  echo "Configuring environment variables..."
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      echo "$line" >> "$tmp"
    else
      local var="${line%%=*}"
      local default="${line#*=}"
      local current=""
      if [ -f .env ]; then
        current=$(grep -E "^${var}=" .env | cut -d= -f2-)
      fi
      local prompt="${current:-$default}"
      read -p "Enter value for $var [$prompt]: " value
      value=${value:-$prompt}
      echo "$var=$value" >> "$tmp"
    fi
  done < "$template"
  mv "$tmp" .env
}

print_config_summary() {
  echo "Configuration summary:"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    echo "  $line"
  done < .env
  echo
  echo "Transcode node requires these values:" 
  for var in DATA_DIR MINIO_ENDPOINT MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_BUCKET_PREVIEWS MINIO_BUCKET_HLS; do
    local value=$(grep -E "^$var=" .env | cut -d= -f2-)
    echo "  $var=$value"
  done
}

# Configure environment interactively each run
configure_env
set -a
source .env
set +a

mkdir -p \
  "$DATA_DIR/redis" \
  "$DATA_DIR/app-postgres" \
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
read -p "Enter choice [1-3]: " choice

case "$choice" in
  1)
    serve_compose=$(prepare_compose_with_free_ports compose.serve.yml)
    docker compose --project-directory "$REPO_DIR" -f "$serve_compose" up -d
    display_ports "$serve_compose"
    rm "$serve_compose"
    print_config_summary
    ;;
  2)
    docker compose --project-directory "$REPO_DIR" -f compose.transcode.yml up -d
    display_ports compose.transcode.yml
    ;;
  3)
    serve_compose=$(prepare_compose_with_free_ports compose.serve.yml)
    docker compose --project-directory "$REPO_DIR" -f "$serve_compose" -f compose.transcode.yml up -d
    display_ports "$serve_compose" compose.transcode.yml
    rm "$serve_compose"
    print_config_summary
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
