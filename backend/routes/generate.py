import os

from fastapi import APIRouter
from fastapi import HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.services.request_limits import enforce_previous_code_limit, enforce_prompt_limit
from backend.services.generator import stream_generated_text

router = APIRouter(prefix="", tags=["generate"])


class GenerateRequest(BaseModel):
    prompt: str
    previous_code: str | None = None


@router.get("/generate")
async def generate_help() -> dict:
    return {
        "message": "Use POST /generate with JSON: { 'prompt': '...', 'previous_code': '...' (optional) }",
        "response_shape": {
            "steps": [
                {"title": "Create Baseplate", "code": "-- Roblox Lua code..."},
                {"title": "Add Spawn", "code": "-- Roblox Lua code..."},
            ]
        },
        "fix_endpoint": {
            "path": "/fix",
            "method": "POST",
            "request": {"error_message": "...", "code": "..."},
            "response": "streamed text/plain (fixed Roblox Lua code only)",
        },
    }


@router.post("/generate")
async def generate(payload: GenerateRequest) -> StreamingResponse:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    enforce_prompt_limit(payload.prompt)
    if payload.previous_code is not None:
        enforce_previous_code_limit(payload.previous_code)

    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")

    return StreamingResponse(
        stream_generated_text(prompt=payload.prompt, previous_code=payload.previous_code),
        media_type="application/json; charset=utf-8",
    )
