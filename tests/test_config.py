import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app  # noqa: E402

client = TestClient(app)


def auth_headers():
    return {"Authorization": "Bearer fake-jwt"}


def test_config_get_and_update(tmp_path):
    # Ensure we start with defaults
    resp = client.get("/admin/config", headers=auth_headers())
    assert resp.status_code == 200
    data = resp.json()
    assert "download_dir" in data

    data["download_dir"] = "/new"
    data["ffmpeg_preset"] = "slow"

    resp = client.put("/admin/config", json=data, headers=auth_headers())
    assert resp.status_code == 200
    assert resp.json() == data

    # Ensure subsequent GET returns updated data
    resp = client.get("/admin/config", headers=auth_headers())
    assert resp.status_code == 200
    assert resp.json() == data


def test_config_requires_auth():
    resp = client.get("/admin/config")
    assert resp.status_code == 403
