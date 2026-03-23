import os
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.services.request_limits import enforce_prompt_limit
from backend.services.tool_calls import plan_tool_calls

router = APIRouter(prefix="/tools", tags=["tools"])


class ToolsPlanRequest(BaseModel):
    prompt: str


@router.post("/plan")
async def tools_plan(payload: ToolsPlanRequest) -> dict[str, Any]:
    if not payload.prompt.strip():
        raise HTTPException(status_code=400, detail="'prompt' must not be empty")

    enforce_prompt_limit(payload.prompt)

    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY is not set")

    return await plan_tool_calls(payload.prompt)
