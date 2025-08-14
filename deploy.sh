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
    docker compose -f compose.serve.yml up -d
    ;;
  2)
    docker compose -f compose.transcode.yml up -d
    ;;
  3)
    docker compose -f compose.serve.yml -f compose.transcode.yml up -d
    ;;
  *)
    echo "Invalid choice. Exiting."
    exit 1
    ;;
esac
