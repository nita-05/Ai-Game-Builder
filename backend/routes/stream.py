from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.services.request_limits import enforce_previous_code_limit, enforce_prompt_limit
from backend.services.ai_stream import (
    create_session,
    get_session_snapshot,
    start_background_stream,
    start_background_stream_live,
    start_background_stream_refine,
    touch_session,
)

router = APIRouter(prefix="", tags=["stream"])


class StartRequest(BaseModel):
    prompt: str


class RefineStartRequest(BaseModel):
    prompt: str
    previous_code: str


@router.post("/start")
async def start(payload: StartRequest) -> dict:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    enforce_prompt_limit(payload.prompt)

    session_id = await create_session(payload.prompt)
    await start_background_stream(session_id=session_id, prompt=payload.prompt)
    return {"session_id": session_id}


@router.post("/start_live")
async def start_live(payload: StartRequest) -> dict:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    enforce_prompt_limit(payload.prompt)

    session_id = await create_session(payload.prompt)
    await start_background_stream_live(session_id=session_id, prompt=payload.prompt)
    return {"session_id": session_id}


@router.post("/refine_start")
async def refine_start(payload: RefineStartRequest) -> dict:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    if not payload.previous_code.strip():
        raise HTTPException(status_code=400, detail="'previous_code' must not be empty")

    enforce_prompt_limit(payload.prompt)
    enforce_previous_code_limit(payload.previous_code)

    session_id = await create_session(payload.prompt)
    await start_background_stream_refine(
        session_id=session_id,
        prompt=payload.prompt,
        previous_code=payload.previous_code,
    )
    return {"session_id": session_id}


@router.get("/stream/{session_id}")
async def stream(session_id: str) -> dict:
    await touch_session(session_id)
    snapshot = await get_session_snapshot(session_id)
    if not snapshot:
        raise HTTPException(status_code=404, detail="session_id not found")

    return {
        "session_id": session_id,
        "text": snapshot.get("text", ""),
        "done": snapshot.get("done", False),
        "error": snapshot.get("error"),
    }
