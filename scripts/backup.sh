#!/bin/sh
# Backup App DB and media directories to MinIO via rclone
set -e

PG_DSN="${PG_DSN:-postgresql://mediahub:mediahub@app-postgres:5432/mediahub}"
BACKUP_REMOTE="${BACKUP_REMOTE:-minio:seedbox-backup}"  # rclone remote
MEDIA_DIR="${MEDIA_DIR:-/data}"
DATE=$(date +%Y%m%d%H%M%S)
TMPFILE="/tmp/appdb_$DATE.sql"

echo "Dumping database to $TMPFILE" >&2
pg_dump "$PG_DSN" > "$TMPFILE"

echo "Uploading DB dump" >&2
rclone copy "$TMPFILE" "$BACKUP_REMOTE/db/"

if [ -d "$MEDIA_DIR" ]; then
  echo "Syncing media directory" >&2
  rclone sync "$MEDIA_DIR" "$BACKUP_REMOTE/media/"
fi

rm -f "$TMPFILE"
echo "Backup completed" >&2
