import os

from openai import AsyncOpenAI


SYSTEM_PROMPT = (
    "You are the Planner Agent for a Roblox game builder system. "
    "You receive a user request and produce a concise plan of build steps. "
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

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    return {"steps": []}
