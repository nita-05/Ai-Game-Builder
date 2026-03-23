import json

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from backend.services.orchestrator import orchestrate_stream
from backend.services.request_limits import enforce_prompt_limit

router = APIRouter(prefix="/orchestrate", tags=["orchestrate"])


class OrchestrateRequest(BaseModel):
    prompt: str


@router.post("/stream")
async def orchestrate_stream_endpoint(payload: OrchestrateRequest) -> StreamingResponse:
    enforce_prompt_limit(payload.prompt)

    async def gen():
        async for event in orchestrate_stream(payload.prompt):
            yield json.dumps(event) + "\n"

    return StreamingResponse(gen(), media_type="application/x-ndjson; charset=utf-8")
