#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Update repository
if [ -d .git ]; then
  echo "Updating repository..."
  git pull --rebase
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

DATA_DIR=${DATA_DIR:-/opt/seedbox}

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
docker compose -f compose.serve.yml -f compose.transcode.yml up -d
