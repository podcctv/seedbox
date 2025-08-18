import sys
from pathlib import Path

from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT))

import api.main as main

client = TestClient(main.app)


def test_search_endpoint():
    response = client.get('/search', params={'q': 'test'})
    assert response.status_code == 503
    assert response.json()["detail"] == "bitmagnet database unavailable"


class DummyConn:
    def __init__(self):
        self.calls = []

    async def fetch(self, sql, param=None):
        self.calls.append((sql, param))
        if 'plainto_tsquery' in sql:
            return []
        return [
            {
                'id': '1',
                'torrent_name': 'demo',
                'title': None,
                'magnet': 'magnet:?xt=urn:btih:1',
                'size': 123,
            }
        ]


class DummyAcquire:
    def __init__(self, conn):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, exc_type, exc, tb):
        return False


class DummyPool:
    def __init__(self):
        self.conn = DummyConn()

    def acquire(self):
        return DummyAcquire(self.conn)


def test_search_fallback_ilike(monkeypatch):
    pool = DummyPool()
    monkeypatch.setattr(main, 'bitmagnet_pool', pool)
    response = client.get('/search', params={'q': 'demo'})
    assert response.status_code == 200
    data = response.json()
    assert data['query'] == 'demo'
    assert data['results'] and data['results'][0]['torrent_name'] == 'demo'
