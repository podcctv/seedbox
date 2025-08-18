import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app  # noqa: E402

client = TestClient(app)


def auth_headers():
    return {"Authorization": "Bearer fake-jwt"}


def test_admin_query_requires_auth():
    resp = client.post("/admin/query", json={"sql": "SELECT 1"})
    assert resp.status_code == 403


def test_admin_query_with_auth():
    resp = client.post(
        "/admin/query", json={"sql": "SELECT 1"}, headers=auth_headers()
    )
    assert resp.status_code == 200
    assert "rows" in resp.json()
