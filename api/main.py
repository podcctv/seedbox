from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional, Any
import logging
import os

try:  # pragma: no cover - optional dependency
    import asyncpg
except ModuleNotFoundError:  # pragma: no cover - asyncpg is optional
    asyncpg = None

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

BITMAGNET_RO_DSN = os.environ.get("BITMAGNET_RO_DSN", "")

init_db()
current_config = load_config()
bitmagnet_pool: Optional[Any] = None


async def ensure_bitmagnet_pool() -> Optional[Any]:
    """Ensure the Bitmagnet connection pool is available.

    If the pool failed to initialize at startup (for example if the database
    was temporarily unreachable), this function will attempt to create it on
    demand when a request needs database access.
    """
    global bitmagnet_pool
    if bitmagnet_pool is None and asyncpg is not None:
        try:
            bitmagnet_pool = await asyncpg.create_pool(
                BITMAGNET_RO_DSN, min_size=1, max_size=5
            )
        except Exception as exc:  # pragma: no cover - network errors
            logger.warning("bitmagnet pool unavailable: %s", exc)
            bitmagnet_pool = None
    return bitmagnet_pool


@app.on_event("startup")
async def startup() -> None:
    global bitmagnet_pool
    if asyncpg is None:
        logger.warning("asyncpg not installed; bitmagnet pool disabled")
        bitmagnet_pool = None
        return
    try:
        bitmagnet_pool = await asyncpg.create_pool(
            BITMAGNET_RO_DSN, min_size=1, max_size=5
        )
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
    if not (payload.username == "admin" and payload.password == "admin"):
        logger.info("invalid login username=%s", payload.username)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    role = "admin"
    exp = datetime.utcnow() + timedelta(hours=TOKEN_EXP_HOURS)
    logger.info("login username=%s role=%s", payload.username, role)
    return LoginResponse(token=FAKE_TOKEN, role=role, exp=exp)


def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.scheme.lower() != "bearer" or credentials.credentials != FAKE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token"
        )
    return True


@app.get("/auth/verify")
async def auth_verify(_: bool = Depends(verify_token)):
    return {"status": "ok"}


@app.get("/search")
async def search(q: Optional[str] = None):
    if not q:
        return {"results": [], "query": q}
    if await ensure_bitmagnet_pool() is None:
        raise HTTPException(status_code=503, detail="bitmagnet database unavailable")
    try:
        async with bitmagnet_pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT
                    encode(tc.info_hash, 'hex') AS id,
                    t.name AS torrent_name,
                    c.title,
                    'magnet:?xt=urn:btih:' || encode(tc.info_hash, 'hex') AS magnet,
                    tc.size
                FROM public.torrent_contents tc
                LEFT JOIN public.torrents t
                       ON t.info_hash = tc.info_hash
                LEFT JOIN public.content c
                       ON c.type   = tc.content_type
                      AND c.source = tc.content_source
                      AND c.id     = tc.content_id
                WHERE tc.tsv @@ websearch_to_tsquery('simple', $1)
                ORDER BY tc.created_at DESC
                LIMIT 10
                """,
                q,
            )

            # Fallback for languages without full-text support (e.g. Chinese)
            if not rows:
                rows = await conn.fetch(
                    """
                    SELECT
                        encode(t.info_hash, 'hex') AS id,
                        t.name AS torrent_name,
                        NULL        AS title,
                        'magnet:?xt=urn:btih:' || encode(t.info_hash, 'hex') AS magnet,
                        t.size
                    FROM public.torrents t
                    WHERE t.name ILIKE $1
                    ORDER BY t.created_at DESC
                    LIMIT 10
                    """,
                    f"%{q}%",
                )
        results = [dict(r) for r in rows]
        return {"results": results, "query": q}
    except Exception as exc:
        logger.error("search failed q=%s err=%s", q, exc)
        return {"results": [], "query": q}


@app.get("/videos")
async def videos():
    if await ensure_bitmagnet_pool() is None:
        raise HTTPException(status_code=503, detail="bitmagnet database unavailable")
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
      encode(tc.info_hash, 'hex') AS infohash,
      t.name     AS torrent_name,
      'magnet:?xt=urn:btih:' || encode(tc.info_hash, 'hex') AS magnet,
      t.size
    FROM public.content c
    LEFT JOIN public.content_attributes ca_year
      ON ca_year.content_type = c.type
     AND ca_year.content_source = c.source
     AND ca_year.content_id = c.id
     AND ca_year.key = (SELECT key FROM year_key)
    JOIN public.torrent_contents tc
      ON tc.content_type = c.type
     AND tc.content_source = c.source
     AND tc.content_id = c.id
    JOIN public.torrents t
      ON t.info_hash = tc.info_hash
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


class SQLQuery(BaseModel):
    sql: str


@app.post("/admin/query")
async def admin_query(q: SQLQuery, _: bool = Depends(verify_token)):
    if await ensure_bitmagnet_pool() is None:
        raise HTTPException(status_code=503, detail="bitmagnet database unavailable")
    try:
        async with bitmagnet_pool.acquire() as conn:
            rows = await conn.fetch(q.sql)
        return {"rows": [dict(r) for r in rows]}
    except Exception as exc:
        logger.error("admin query failed sql=%s err=%s", q.sql, exc)
        raise HTTPException(status_code=400, detail=str(exc))


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
