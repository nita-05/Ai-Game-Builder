from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.services.memory import get_build, get_style, list_builds, save_build, set_style

router = APIRouter(prefix="/memory", tags=["memory"])


class SaveBuildRequest(BaseModel):
    prompt: str
    steps: object | None = None
    scripts: object | None = None
    status: str | None = None
    metadata: object | None = None


class StyleRequest(BaseModel):
    user_id: str
    prefs: object


@router.post("/save_build")
async def save_build_endpoint(payload: SaveBuildRequest) -> dict:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    build_id = await save_build(
        prompt=payload.prompt,
        steps=payload.steps,
        scripts=payload.scripts,
        status=payload.status,
        metadata=payload.metadata,
    )
    return {"build_id": build_id}


@router.get("/builds")
async def list_builds_endpoint(limit: int = 20, offset: int = 0) -> dict:
    items = await list_builds(limit=limit, offset=offset)
    return {"items": items, "limit": limit, "offset": offset}


@router.get("/build/{build_id}")
async def get_build_endpoint(build_id: str) -> dict:
    build = await get_build(build_id)
    if not build:
        raise HTTPException(status_code=404, detail="build not found")
    return build


@router.post("/style")
async def set_style_endpoint(payload: StyleRequest) -> dict:
    if not payload.user_id.strip():
        raise HTTPException(status_code=400, detail="'user_id' must not be empty")

    await set_style(payload.user_id, payload.prefs)
    return {"ok": True}


@router.get("/style/{user_id}")
async def get_style_endpoint(user_id: str) -> dict:
    prefs = await get_style(user_id)
    if not prefs:
        raise HTTPException(status_code=404, detail="style not found")
    return prefs
