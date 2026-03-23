import os

from openai import AsyncOpenAI


SYSTEM_PROMPT = (
    "You are a Roblox Lua code reviewer and validator. "
    "Given a Lua script, detect likely runtime errors, Roblox API misuse, and unsafe patterns. "
    "Return ONLY JSON: {warnings:[string], errors:[string]}. No explanations outside JSON."
)


async def validator_agent(title: str, code: str) -> dict:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": (
                    "SCRIPT_TITLE:\n"
                    + title
                    + "\n\nSCRIPT_CODE:\n"
                    + code
                    + "\n"
                ),
            },
        ],
        temperature=0.1,
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

    return {"warnings": [], "errors": []}
