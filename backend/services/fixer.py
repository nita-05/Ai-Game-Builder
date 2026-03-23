import os
from collections.abc import AsyncIterator

from openai import APIError, AsyncOpenAI


SYSTEM_PROMPT = (
    "You are an expert Roblox Lua developer. "
    "Always generate clean, working, optimized Roblox Lua scripts that are executable inside Roblox Studio. "
    "Output ONLY Roblox Lua code. "
    "No explanations. No markdown. No code fences."
)


def _build_fix_prompt(error_message: str, code: str) -> str:
    return (
        "You will be given Roblox Lua code and an error message. "
        "Analyze the error, fix the code, and return ONLY the corrected Roblox Lua code. "
        "The result must be executable inside Roblox Studio. "
        "Do not include explanations, markdown, or code fences.\n\n"
        f"ERROR_MESSAGE:\n{error_message}\n\n"
        f"CODE:\n{code}\n"
    )


async def stream_fixed_code(error_message: str, code: str) -> AsyncIterator[str]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        yield "-- ERROR: OPENAI_API_KEY is not set\n"
        return

    client = AsyncOpenAI(api_key=api_key)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": _build_fix_prompt(error_message=error_message, code=code)},
    ]

    try:
        stream = await client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages=messages,
            stream=True,
            temperature=0.1,
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
