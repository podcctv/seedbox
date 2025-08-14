import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app

client = TestClient(app)

def test_healthz():
    response = client.get('/healthz')
    assert response.status_code == 200
    assert response.json() == {'status': 'ok'}
