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

# Create .env if missing
if [ ! -f .env ]; then
  echo "Generating .env configuration..."
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      echo "$line" >> .env
    else
      var="${line%%=*}"
      default="${line#*=}"
      read -p "Enter value for $var [$default]: " value
      value=${value:-$default}
      echo "$var=$value" >> .env
    fi
  done < .env.example
fi

set -a
source .env
set +a

# Prompt for persistent data directory
default_dir=${DATA_DIR:-/opt/seedbox}
read -p "Enter data directory [${default_dir}]: " DATA_DIR_INPUT
DATA_DIR=${DATA_DIR_INPUT:-$default_dir}
export DATA_DIR

# Persist the chosen directory in .env
if [ -f .env ]; then
  if grep -q '^DATA_DIR=' .env; then
    sed -i "s|^DATA_DIR=.*|DATA_DIR=$DATA_DIR|" .env
  else
    echo "DATA_DIR=$DATA_DIR" >> .env
  fi
fi

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
    rm "$serve_compose"
    ;;
  2)
    docker compose --project-directory "$REPO_DIR" -f compose.transcode.yml up -d
    ;;
  3)
    serve_compose=$(prepare_compose_with_free_ports compose.serve.yml)
    docker compose --project-directory "$REPO_DIR" -f "$serve_compose" -f compose.transcode.yml up -d
    rm "$serve_compose"
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
