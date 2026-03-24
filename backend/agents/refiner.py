import os
from collections.abc import AsyncIterator

from openai import APIError, AsyncOpenAI


SYSTEM_PROMPT = "Modify the given Roblox Lua code based on user request without breaking existing functionality."


JSON_SYSTEM_PROMPT = (
    "You are the Refiner Agent. "
    "Given existing Roblox Lua scripts and a new requirement, return only the necessary updates. "
    "Output ONLY JSON: {steps:[{title, code}]}. "
    "Only include scripts that changed. No explanations, no markdown."
)


async def refiner_agent(prompt: str, previous_code: str) -> dict:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": JSON_SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_message(prompt, previous_code)},
        ],
        temperature=0.2,
        response_format={"type": "json_object"},
    )

    content = resp.choices[0].message.content or "{}"
    return _safe_json_loads(content)


async def refiner_agent_stream(prompt: str, previous_code: str) -> AsyncIterator[str]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        yield '{"steps":[{"title":"Error","code":"-- ERROR: OPENAI_API_KEY is not set"}]}'
        return

    client = AsyncOpenAI(api_key=api_key)
    try:
        stream = await client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages=[
                {"role": "system", "content": JSON_SYSTEM_PROMPT},
                {"role": "user", "content": _build_user_message(prompt, previous_code)},
            ],
            stream=True,
            temperature=0.2,
            response_format={"type": "json_object"},
        )

        async for event in stream:
            delta = event.choices[0].delta
            content = getattr(delta, "content", None)
            if content:
                yield content

    except APIError as e:
        yield '{"steps":[{"title":"Error","code":' + _json_str(f"-- ERROR: OpenAI API error: {e}") + "}]}"
    except Exception as e:
        yield '{"steps":[{"title":"Error","code":' + _json_str(f"-- ERROR: Unexpected error: {e}") + "}]}"


async def refiner_agent_code(prompt: str, existing_code: str) -> str:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": (
                    "USER_REQUEST:\n"
                    + prompt
                    + "\n\nEXISTING_CODE:\n"
                    + existing_code
                    + "\n\nReturn ONLY the updated Roblox Lua code. No explanations.\n"
                ),
            },
        ],
        temperature=0.2,
    )

    return resp.choices[0].message.content or ""


def _build_user_message(prompt: str, previous_code: str) -> str:
    return (
        "NEW_REQUIREMENT:\n"
        + prompt
        + "\n\nEXISTING_CODEBASE:\n"
        + previous_code
        + "\n"
    )


def _json_str(value: str) -> str:
    import json

    return json.dumps(value)


def _safe_json_loads(text: str) -> dict:
    import json

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    return {"steps": []}
