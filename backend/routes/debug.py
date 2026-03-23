import os

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.agents.debugger import debugger_agent_code
from backend.services.request_limits import enforce_previous_code_limit

router = APIRouter(prefix="", tags=["debug"])


class DebugRequest(BaseModel):
    error_message: str
    code: str


async def _stream_debugged_code(error_message: str, code: str):
    if not os.getenv("OPENAI_API_KEY"):
        yield "-- ERROR: OPENAI_API_KEY is not set\n"
        return

    fixed = await debugger_agent_code(error_message=error_message, code=code)
    yield fixed


@router.post("/debug")
async def debug(payload: DebugRequest) -> StreamingResponse:
    if not payload.error_message.strip():
        raise HTTPException(status_code=400, detail="'error_message' must not be empty")

    if not payload.code.strip():
        raise HTTPException(status_code=400, detail="'code' must not be empty")

    enforce_previous_code_limit(payload.code)

    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")

    return StreamingResponse(
        _stream_debugged_code(error_message=payload.error_message, code=payload.code),
        media_type="text/plain; charset=utf-8",
    )
