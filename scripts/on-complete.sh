#!/bin/sh
# qBittorrent on completion script
# Usage: on-complete.sh "%I" "%N" "%R"
INFOHASH="$1"
NAME="$2"
ROOT="$3"
WEBHOOK_URL="${API_PUBLIC_BASE:-http://api:8000}/webhooks/fetcher_done"

echo "Notifying API of completed download: $INFOHASH" >&2
curl -s -X POST "$WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"hash\": \"$INFOHASH\", \"name\": \"$NAME\", \"root\": \"$ROOT\"}"
