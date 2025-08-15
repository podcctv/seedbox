import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

from api.main import app

client = TestClient(app)

def test_search_endpoint():
    response = client.get('/search', params={'q': 'test'})
    assert response.status_code == 200
    data = response.json()
    assert 'results' in data
    assert 'query' in data and data['query'] == 'test'
    assert isinstance(data['results'], list)
    if data['results']:
        assert 'magnet' in data['results'][0]
