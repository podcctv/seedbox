"""Worker node utilities for MediaHub Seedbox."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

import requests

API_URL = os.getenv("API_URL", "http://localhost:28000")
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


def process(job: dict) -> int:
    """Generate preview for a job and report completion."""
    job_id = job["id"]
    video_path = job["path"]
    sprite_path = Path(video_path).with_suffix(".jpg")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            video_path,
            "-vf",
            "fps=1/10,scale=320:-1,tile=5x5",
            str(sprite_path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return report_done(job_id, str(sprite_path))


def run(poll_interval: int = 5) -> None:
    """Continuously poll for jobs and process them."""
    while True:
        try:
            job = next_job()
        except requests.HTTPError as exc:
            if exc.response is not None and exc.response.status_code in (204, 404):
                time.sleep(poll_interval)
                continue
            raise
        process(job)


if __name__ == "__main__":
    run()


__all__ = ["next_job", "report_done", "process", "run"]
