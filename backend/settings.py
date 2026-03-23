import os


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or str(raw).strip() == "":
        return default
    try:
        return int(raw)
    except Exception:
        return default


OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

OPENAI_STREAM_TIMEOUT_SECONDS = _int_env("OPENAI_STREAM_TIMEOUT_SECONDS", 120)
SESSION_IDLE_TIMEOUT_SECONDS = _int_env("SESSION_IDLE_TIMEOUT_SECONDS", 15)

MEMORY_DB_PATH = os.getenv("MEMORY_DB_PATH", "backend/memory.db")
MEMORY_USER_ID = os.getenv("MEMORY_USER_ID", "default")

STREAM_SESSIONS_DB_PATH = os.getenv("STREAM_SESSIONS_DB_PATH", "backend/stream_sessions.db")

RATE_LIMIT_REQUESTS_PER_MINUTE = _int_env("RATE_LIMIT_REQUESTS_PER_MINUTE", 10)
MAX_PROMPT_CHARS = _int_env("MAX_PROMPT_CHARS", 10_000)
MAX_PREVIOUS_CODE_CHARS = _int_env("MAX_PREVIOUS_CODE_CHARS", 200_000)
STREAM_SESSION_RETENTION_SECONDS = _int_env("STREAM_SESSION_RETENTION_SECONDS", 3600)

APP_API_KEY = os.getenv("APP_API_KEY", "")
