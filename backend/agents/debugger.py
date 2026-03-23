import os

from openai import AsyncOpenAI


SYSTEM_PROMPT = "You are a Roblox debugging expert. Fix errors and return clean working code only."


JSON_SYSTEM_PROMPT = (
    "You are the Debugger Agent. "
    "Given Roblox Lua code and an error message, return a corrected version. "
    "Output ONLY JSON: {fixed_code: string}. No explanations, no markdown."
)


async def debugger_agent(error_message: str, code: str) -> dict:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": JSON_SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_message(error_message, code)},
        ],
        temperature=0.1,
    )

    content = resp.choices[0].message.content or "{}"
    return _safe_json_loads(content)


async def debugger_agent_code(error_message: str, code: str) -> str:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_message(error_message, code)},
        ],
        temperature=0.1,
    )

    return resp.choices[0].message.content or ""


def _build_user_message(error_message: str, code: str) -> str:
    return (
        "ERROR_MESSAGE:\n"
        + error_message
        + "\n\nCODE:\n"
        + code
        + "\n"
    )


def _safe_json_loads(text: str) -> dict:
    import json

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    return {"fixed_code": ""}
