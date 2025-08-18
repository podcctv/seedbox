#!/usr/bin/env bash
set -euo pipefail

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
