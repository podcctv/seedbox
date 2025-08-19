#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"

# Load or create Bitmagnet database settings
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  read -p "Bitmagnet DB host: " BITMAGNET_DB_HOST
  read -p "Bitmagnet DB port: " BITMAGNET_DB_PORT
  read -p "Bitmagnet DB user: " BITMAGNET_DB_USER
  read -s -p "Bitmagnet DB password: " BITMAGNET_DB_PASS
  echo
  export BITMAGNET_DB_HOST BITMAGNET_DB_PORT BITMAGNET_DB_USER BITMAGNET_DB_PASS
  cat >"$ENV_FILE" <<EOF
BITMAGNET_DB_HOST=$BITMAGNET_DB_HOST
BITMAGNET_DB_PORT=$BITMAGNET_DB_PORT
BITMAGNET_DB_USER=$BITMAGNET_DB_USER
BITMAGNET_DB_PASS=$BITMAGNET_DB_PASS
EOF
fi

# Deploy download and worker nodes using docker compose files if present
for dir in download worker; do
  compose_file="$dir/docker-compose.yml"
  if [[ -f "$compose_file" ]]; then
    (
      cd "$dir"
      docker compose up -d
    )
  else
    echo "Missing $compose_file; skipping."
  fi
done
