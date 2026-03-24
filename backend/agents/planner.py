import os
import re

from openai import AsyncOpenAI


SYSTEM_PROMPT = (
    "You are the Planner Agent for a Roblox game builder system. "
    "You receive a user request and produce a concise but COMPLETE plan of build steps. "
    "For a new game request, always include enough steps to make a playable baseline "
    "(core gameplay loop, player progression/score, UI feedback, spawn/restart or fail handling). "
    "Prefer 4-8 steps for first-pass playable output. "
    "Use explorer-style titles such as Service/Folder/ScriptName. "
    "Output ONLY JSON with a 'steps' array of objects: {title, description}. "
    "No explanations outside JSON."
)


async def planner_agent(prompt: str) -> dict:
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


def _safe_json_loads(text: str) -> dict:
    import json

    raw = str(text or "").strip()
    if raw == "":
        return {"steps": []}

    candidates = [raw]

    # Handle fenced JSON blocks.
    fence_match = re.search(r"```(?:json)?\s*(\{[\s\S]*\})\s*```", raw, flags=re.IGNORECASE)
    if fence_match:
        candidates.append(fence_match.group(1))

    # Handle mixed prose where JSON object exists inside.
    obj_match = re.search(r"(\{[\s\S]*\})", raw)
    if obj_match:
        candidates.append(obj_match.group(1))

    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            continue

    return {"steps": []}
