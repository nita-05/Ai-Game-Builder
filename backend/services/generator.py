import os
import json
from collections.abc import AsyncIterator

from openai import APIError, AsyncOpenAI


SYSTEM_PROMPT = (
    "You are an expert Roblox Lua developer. "
    "Always generate clean, working, optimized Roblox Lua scripts that are executable inside Roblox Studio. "
    "Output ONLY Roblox Lua code in script bodies. "
    "No explanations. No markdown. No code fences."
)


def _build_user_prompt(prompt: str, previous_code: str | None) -> str:
    if previous_code:
        return (
            "You are refining an existing Roblox game implementation.\n"
            "You will receive the current codebase (multiple scripts) and a new user request.\n"
            "Make ONLY the necessary changes to satisfy the request and keep everything else unchanged.\n"
            "Return ONLY the updated/added scripts as NDJSON, one JSON object per line.\n"
            "Do NOT output scripts that do not need any change.\n"
            "Each line must be a JSON object with EXACT keys: title, code.\n"
            "- title: use the existing script name when editing an existing script; use a clear new script name when adding.\n"
            "- code: valid Roblox Lua code (no markdown, no explanations).\n"
            "If no changes are required, output exactly one line with {\"title\":\"No_Changes\",\"code\":\"-- No changes needed\"}.\n\n"
            f"USER_REQUEST:\n{prompt}\n\n"
            f"EXISTING_CODEBASE:\n{previous_code}\n"
        )

    return (
        "You are building a Roblox game. Return structured build steps.\n"
        "Output MUST be NDJSON (one JSON object per line). Do NOT wrap in a JSON array/object.\n"
        "Each line must be a JSON object with EXACT keys: title, code.\n"
        "- title: short step title (will be used as the Script name)\n"
        "- code: valid Roblox Lua code for that step (no markdown fences, no explanations)\n"
        "Return ONLY NDJSON lines.\n\n"
        f"USER_REQUEST:\n{prompt}\n"
    )


def _validate_step(step: object) -> dict | None:
    if not isinstance(step, dict):
        return None

    title = step.get("title")
    code = step.get("code")
    if not isinstance(title, str) or not title.strip():
        return None
    if not isinstance(code, str) or not code.strip():
        return None

    return {"title": title.strip(), "code": code}


async def stream_generated_text(prompt: str, previous_code: str | None = None) -> AsyncIterator[str]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        yield json.dumps({"steps": [{"title": "Error", "code": "-- ERROR: OPENAI_API_KEY is not set"}]})
        return

    client = AsyncOpenAI(api_key=api_key)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": _build_user_prompt(prompt=prompt, previous_code=previous_code)},
    ]

    try:
        yield '{"steps":['
        first = True
        buffer = ""

        stream = await client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
            messages=messages,
            stream=True,
            temperature=0.2,
        )

        async for event in stream:
            delta = event.choices[0].delta
            content = getattr(delta, "content", None)
            if content:
                buffer += content
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        parsed = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    step = _validate_step(parsed)
                    if not step:
                        continue

                    if not first:
                        yield ","
                    first = False
                    yield json.dumps(step)

        leftover = buffer.strip()
        if leftover:
            try:
                parsed = json.loads(leftover)
                step = _validate_step(parsed)
                if step:
                    if not first:
                        yield ","
                    yield json.dumps(step)
            except json.JSONDecodeError:
                pass

        yield "]}"

    except APIError as e:
        error_step = {"title": "Error", "code": f"-- ERROR: OpenAI API error: {e}"}
        if "first" in locals():
            if not first:
                yield ","
            yield json.dumps(error_step)
            yield "]}"
        else:
            yield json.dumps({"steps": [error_step]})
    except Exception as e:
        error_step = {"title": "Error", "code": f"-- ERROR: Unexpected error: {e}"}
        if "first" in locals():
            if not first:
                yield ","
            yield json.dumps(error_step)
            yield "]}"
        else:
            yield json.dumps({"steps": [error_step]})