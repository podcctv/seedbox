import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app

client = TestClient(app)

def test_videos_endpoint():
    response = client.get('/videos')
    assert response.status_code == 200
    data = response.json()
    assert 'videos' in data
    assert isinstance(data['videos'], list)
