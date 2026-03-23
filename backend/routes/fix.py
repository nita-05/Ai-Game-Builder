import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.services.request_limits import enforce_previous_code_limit
from backend.services.fixer import stream_fixed_code

router = APIRouter(prefix="", tags=["fix"])


class FixRequest(BaseModel):
    error_message: str
    code: str


@router.post("/fix")
async def fix(payload: FixRequest) -> StreamingResponse:
    if not payload.error_message.strip():
        raise HTTPException(status_code=400, detail="'error_message' must not be empty")

    if not payload.code.strip():
        raise HTTPException(status_code=400, detail="'code' must not be empty")

    enforce_previous_code_limit(payload.code)

    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")

    return StreamingResponse(
        stream_fixed_code(error_message=payload.error_message, code=payload.code),
        media_type="text/plain; charset=utf-8",
    )
