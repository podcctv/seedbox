import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app

client = TestClient(app)


def test_auth_verify_requires_token():
    resp = client.get("/auth/verify")
    assert resp.status_code == 403


def test_auth_verify_with_token():
    headers = {"Authorization": "Bearer fake-jwt"}
    resp = client.get("/auth/verify", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_auth_login_success():
    resp = client.post(
        "/auth/login", json={"username": "admin", "password": "admin"}
    )
    assert resp.status_code == 200
    assert resp.json()["token"] == "fake-jwt"


def test_auth_login_failure():
    resp = client.post(
        "/auth/login", json={"username": "user", "password": "wrong"}
    )
    assert resp.status_code == 401
