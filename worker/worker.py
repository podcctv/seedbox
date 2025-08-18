"""Worker node utilities for MediaHub Seedbox."""

from __future__ import annotations

import os
import requests

API_URL = os.getenv("API_URL", "http://localhost:8000")
API_TOKEN = os.getenv("API_TOKEN", "token")


def next_job() -> dict:
    """Fetch next job from download node."""
    resp = requests.post(
        f"{API_URL}/jobs/next", headers={"X-Auth": API_TOKEN}, timeout=5
    )
    resp.raise_for_status()
    return resp.json()


def report_done(job_id: int, sprite_path: str) -> int:
    """Report job completion back to download node."""
    with open(sprite_path, "rb") as fh:
        files = {"sprite": fh}
        resp = requests.post(
            f"{API_URL}/jobs/{job_id}/done",
            files=files,
            headers={"X-Auth": API_TOKEN},
            timeout=5,
        )
    resp.raise_for_status()
    return resp.status_code


__all__ = ["next_job", "report_done"]
