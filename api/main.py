from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional
import logging

from .config import AppConfig, init_db, load_config, save_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("audit")

app = FastAPI(title="MediaHub API")

security = HTTPBearer()

FAKE_TOKEN = "fake-jwt"
TOKEN_EXP_HOURS = 72

init_db()
current_config = load_config()


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
    # Placeholder search implementation
    return {"results": [], "query": q}


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
