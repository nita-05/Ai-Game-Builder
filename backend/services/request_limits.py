from fastapi import HTTPException

from backend.settings import MAX_PREVIOUS_CODE_CHARS, MAX_PROMPT_CHARS


def enforce_prompt_limit(prompt: str) -> None:
    if len(prompt) > MAX_PROMPT_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"'prompt' too large (max {MAX_PROMPT_CHARS} chars)",
        )


def enforce_previous_code_limit(previous_code: str) -> None:
    if len(previous_code) > MAX_PREVIOUS_CODE_CHARS:
        raise HTTPException(
            status_code=413,
            detail=f"'previous_code' too large (max {MAX_PREVIOUS_CODE_CHARS} chars)",
        )
