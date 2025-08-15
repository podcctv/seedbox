from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional
import logging
import os
import asyncpg

from .config import AppConfig, init_db, load_config, save_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("audit")

app = FastAPI(title="MediaHub API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()

FAKE_TOKEN = "fake-jwt"
TOKEN_EXP_HOURS = 72

init_db()
current_config = load_config()

BITMAGNET_RO_DSN = os.environ.get(
    "BITMAGNET_RO_DSN",
    "postgresql://postgres@84.54.3.69:5433/bitmagnet",
)
bitmagnet_pool: Optional[asyncpg.Pool] = None


@app.on_event("startup")
async def startup() -> None:
    global bitmagnet_pool
    try:
        bitmagnet_pool = await asyncpg.create_pool(BITMAGNET_RO_DSN, min_size=1, max_size=5)
    except Exception as exc:
        logger.warning("bitmagnet pool unavailable: %s", exc)
        bitmagnet_pool = None


@app.on_event("shutdown")
async def shutdown() -> None:
    if bitmagnet_pool:
        await bitmagnet_pool.close()


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    token: str
    role: str
    exp: datetime


class FetchTask(BaseModel):
    infohash: Optional[str] = None
    uri: Optional[str] = None


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.post("/auth/login", response_model=LoginResponse)
async def auth_login(payload: LoginRequest):
    # NOTE: This is a stub implementation. Replace with real authentication.
    role = "admin" if payload.username == "admin" else "user"
    exp = datetime.utcnow() + timedelta(hours=TOKEN_EXP_HOURS)
    logger.info("login username=%s role=%s", payload.username, role)
    return LoginResponse(token=FAKE_TOKEN, role=role, exp=exp)


def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.scheme.lower() != "bearer" or credentials.credentials != FAKE_TOKEN:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return True


@app.get("/auth/verify")
async def auth_verify(_: bool = Depends(verify_token)):
    return {"status": "ok"}


@app.get("/search")
async def search(q: Optional[str] = None):
    if not q or bitmagnet_pool is None:
        return {"results": [], "query": q}
    try:
        async with bitmagnet_pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT encode(info_hash, 'hex') AS id, title
                FROM torrent_contents
                WHERE tsv @@ plainto_tsquery('simple', $1)
                ORDER BY created_at DESC
                LIMIT 10
                """,
                q,
            )
        results = [dict(r) for r in rows]
        return {"results": results, "query": q}
    except Exception as exc:
        logger.error("search failed q=%s err=%s", q, exc)
        return {"results": [], "query": q}


@app.get("/videos")
async def videos():
    if bitmagnet_pool is None:
        return {"videos": []}
    query = """
    WITH year_key AS (
      SELECT key
      FROM public.content_attributes
      WHERE key ILIKE '%year%'
      GROUP BY key
      ORDER BY COUNT(*) DESC
      LIMIT 1
    )
    SELECT
      c.id  AS content_id,
      c.title,
      c.type,
      ca_year.value AS year,
      t.id       AS torrent_id,
      t.name     AS torrent_name,
      t.infohash,
      t.size
    FROM public.content c
    LEFT JOIN public.content_attributes ca_year
      ON ca_year.content_type = c.type
     AND ca_year.content_source = c.source
     AND ca_year.content_id = c.id
     AND ca_year.key = (SELECT key FROM year_key)
    JOIN public.torrent_contents tc ON tc.content_id = c.id
    JOIN public.torrents        t  ON t.id         = tc.torrent_id
    ORDER BY NULLIF(ca_year.value,'')::int DESC NULLS LAST,
             t.size DESC NULLS LAST
    LIMIT 50;
    """
    try:
        async with bitmagnet_pool.acquire() as conn:
            rows = await conn.fetch(query)
        return {"videos": [dict(r) for r in rows]}
    except Exception as exc:
        logger.error("videos query failed err=%s", exc)
        return {"videos": []}


@app.post("/tasks/fetch")
async def tasks_fetch(task: FetchTask, _: bool = Depends(verify_token)):
    # Stub: accept task and return queued status
    if not (task.infohash or task.uri):
        raise HTTPException(status_code=400, detail="infohash or uri required")
    logger.info("task.fetch infohash=%s uri=%s", task.infohash, task.uri)
    return {"status": "queued"}


@app.get("/admin/config", response_model=AppConfig)
async def get_config(_: bool = Depends(verify_token)):
    return current_config


@app.put("/admin/config", response_model=AppConfig)
async def update_config(cfg: AppConfig, _: bool = Depends(verify_token)):
    global current_config
    save_config(cfg)
    current_config = cfg
    return current_config


@app.get("/items/{item_id}")
async def get_item(item_id: str):
    # Stub item retrieval
    logger.info("play item=%s", item_id)
    return {"id": item_id, "title": "Sample Item"}


@app.post("/items/{item_id}/favorite")
async def favorite_item(item_id: str, _: bool = Depends(verify_token)):
    return {"id": item_id, "favorited": True}


@app.delete("/items/{item_id}")
async def delete_item(item_id: str, _: bool = Depends(verify_token)):
    logger.info("delete item=%s", item_id)
    return {"id": item_id, "deleted": True}


@app.get("/catalog/{kind}")
async def catalog_list(kind: str):
    if kind not in {"actors", "tags"}:
        raise HTTPException(status_code=404, detail="unknown catalog")
    return {"items": []}


@app.get("/catalog/{kind}/{item_id}")
async def catalog_detail(kind: str, item_id: str):
    if kind not in {"actors", "tags"}:
        raise HTTPException(status_code=404, detail="unknown catalog")
    return {"id": item_id, "kind": kind}


@app.post("/webhooks/fetcher_done")
async def fetcher_done(payload: dict):
    # Stub handler for fetcher completion webhook
    return {"received": payload}


@app.post("/jobs/done")
async def jobs_done(payload: dict):
    # Stub handler for processing completion
    return {"received": payload}
