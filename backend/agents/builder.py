import os
from collections.abc import AsyncIterator

from openai import APIError, AsyncOpenAI


SYSTEM_PROMPT = (
    "You are the Builder Agent. "
    "Given a plan of steps, generate Roblox Lua scripts for each step. "
    "Output ONLY JSON: {steps:[{title, code}]}. "
    "Each 'code' must be executable Roblox Lua. No markdown, no explanations."
)


STREAMING_SYSTEM_PROMPT = (
    "You are the Builder Agent (Streaming). "
    "You generate ONLY Roblox Lua code for a single script step. "
    "Output ONLY Lua code. No explanations. No markdown. No code fences. "
    "Code must be executable inside Roblox Studio. "
    "Prefer modular code and avoid global side-effects when possible."
)


async def builder_agent(prompt: str, plan: dict) -> dict:
    client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = await client.chat.completions.create(
        model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_message(prompt, plan)},
        ],
        temperature=0.2,
    )

    content = resp.choices[0].message.content or "{}"
    return _safe_json_loads(content)


async def builder_agent_stream(step_title: str, step_request: str, previous_code: str | None = None) -> AsyncIterator[str]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        yield "-- ERROR: OPENAI_API_KEY is not set\n"
        return

    client = AsyncOpenAI(api_key=api_key)

    user_message = _build_streaming_user_message(
        step_title=step_title,
        step_request=step_request,
        previous_code=previous_code,
    )

    try:
        stream = await client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages=[
                {"role": "system", "content": STREAMING_SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            stream=True,
            temperature=0.2,
        )

        async for event in stream:
            delta = event.choices[0].delta
            content = getattr(delta, "content", None)
            if content:
                yield content

    except APIError as e:
        yield f"-- ERROR: OpenAI API error: {e}\n"
    except Exception as e:
        yield f"-- ERROR: Unexpected error: {e}\n"


def _build_streaming_user_message(step_title: str, step_request: str, previous_code: str | None) -> str:
    if previous_code:
        return (
            "Refine the existing Roblox Lua script for this step. "
            "Make only necessary changes and return ONLY the updated Lua code.\n\n"
            f"STEP_TITLE:\n{step_title}\n\n"
            f"STEP_REQUEST:\n{step_request}\n\n"
            f"PREVIOUS_CODE:\n{previous_code}\n"
        )

    return (
        "Write a Roblox Lua script for this step and return ONLY the Lua code.\n\n"
        f"STEP_TITLE:\n{step_title}\n\n"
        f"STEP_REQUEST:\n{step_request}\n"
    )


def _build_user_message(prompt: str, plan: dict) -> str:
    import json

    return (
        "USER_REQUEST:\n"
        + prompt
        + "\n\nPLAN_JSON:\n"
        + json.dumps(plan)
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

    return {"steps": []}
