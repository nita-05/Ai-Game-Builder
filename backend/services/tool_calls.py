import json
import os
from typing import Any

from openai import AsyncOpenAI


SYSTEM_PROMPT = (
    "You are a Roblox Studio assistant that outputs tool calls for a plugin to execute. "
    "Return ONLY valid JSON with this exact shape: "
    "{\"tool_calls\":[{\"tool\":\"CreatePart\"|\"CreateFolder\"|\"CreateModel\"|\"CreateScreenGui\",\"args\":{...}}]}. "
    "No explanations, no markdown. "
    "Tools must be safe and minimal. Use workspace-relative parenting only."
)


def _safe_json_loads(text: str) -> dict[str, Any]:
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    return {"tool_calls": []}


async def plan_tool_calls(prompt: str) -> dict[str, Any]:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        temperature=0.2,
    )

    content = resp.choices[0].message.content or "{}"
    return _safe_json_loads(content)
