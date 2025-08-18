#!/usr/bin/env bash
set -euo pipefail

# Deploy download and worker nodes using docker compose files if present
for file in compose.download.yml compose.worker.yml; do
  if [[ -f "$file" ]]; then
    docker compose -f "$file" up -d
  else
    echo "Missing $file; skipping."
  fi
done
