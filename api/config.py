import sqlite3
import os
from pydantic import BaseModel

DB_PATH = os.environ.get("APP_DB", "app.db")


class AppConfig(BaseModel):
    """Application configuration stored in the database."""

    download_dir: str = "/downloads"
    ffmpeg_preset: str = "fast"


def init_db() -> None:
    """Ensure config table exists and contains a default row."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute(
        "CREATE TABLE IF NOT EXISTS config (id INTEGER PRIMARY KEY CHECK (id=1), data TEXT NOT NULL)"
    )
    cur.execute("SELECT id FROM config WHERE id=1")
    if cur.fetchone() is None:
        cur.execute("INSERT INTO config (id, data) VALUES (1, ?)", [AppConfig().model_dump_json()])
    conn.commit()
    conn.close()


def load_config() -> AppConfig:
    """Load configuration from the database."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT data FROM config WHERE id=1")
    row = cur.fetchone()
    conn.close()
    if row:
        return AppConfig.model_validate_json(row[0])
    return AppConfig()


def save_config(cfg: AppConfig) -> None:
    """Persist configuration to the database."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE config SET data=? WHERE id=1", [cfg.model_dump_json()])
    conn.commit()
    conn.close()
