import asyncio
import sqlite3
import time
from typing import Any

from backend.settings import STREAM_SESSIONS_DB_PATH


_db_init_lock = asyncio.Lock()
_db_initialized = False


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(STREAM_SESSIONS_DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


async def init_db() -> None:
    global _db_initialized
    if _db_initialized:
        return

    async with _db_init_lock:
        if _db_initialized:
            return

        def _init() -> None:
            with _connect() as conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS stream_sessions (
                        session_id TEXT PRIMARY KEY,
                        text TEXT NOT NULL DEFAULT '',
                        done INTEGER NOT NULL DEFAULT 0,
                        error TEXT,
                        created_at REAL NOT NULL,
                        last_poll REAL NOT NULL,
                        updated_at REAL NOT NULL
                    )
                    """
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_stream_sessions_updated_at ON stream_sessions(updated_at)"
                )
                conn.commit()

        await asyncio.to_thread(_init)
        _db_initialized = True


async def create_session(session_id: str) -> None:
    await init_db()
    now = time.time()

    def _create() -> None:
        with _connect() as conn:
            conn.execute(
                """
                INSERT INTO stream_sessions(session_id, text, done, error, created_at, last_poll, updated_at)
                VALUES(?, '', 0, NULL, ?, ?, ?)
                """,
                (session_id, now, now, now),
            )
            conn.commit()

    await asyncio.to_thread(_create)


async def append_text(session_id: str, chunk: str) -> None:
    if not chunk:
        return
    await init_db()
    now = time.time()

    def _append() -> None:
        with _connect() as conn:
            conn.execute(
                """
                UPDATE stream_sessions
                SET text = COALESCE(text, '') || ?,
                    updated_at = ?
                WHERE session_id = ?
                """,
                (chunk, now, session_id),
            )
            conn.commit()

    await asyncio.to_thread(_append)


async def set_done(session_id: str, done: bool) -> None:
    await init_db()
    now = time.time()

    def _set() -> None:
        with _connect() as conn:
            conn.execute(
                """
                UPDATE stream_sessions
                SET done = ?,
                    updated_at = ?
                WHERE session_id = ?
                """,
                (1 if done else 0, now, session_id),
            )
            conn.commit()

    await asyncio.to_thread(_set)


async def set_error(session_id: str, error: str) -> None:
    await init_db()
    now = time.time()

    def _set() -> None:
        with _connect() as conn:
            conn.execute(
                """
                UPDATE stream_sessions
                SET error = ?,
                    done = 1,
                    updated_at = ?
                WHERE session_id = ?
                """,
                (error, now, session_id),
            )
            conn.commit()

    await asyncio.to_thread(_set)


async def touch_last_poll(session_id: str) -> None:
    await init_db()
    now = time.time()

    def _touch() -> None:
        with _connect() as conn:
            conn.execute(
                """
                UPDATE stream_sessions
                SET last_poll = ?,
                    updated_at = ?
                WHERE session_id = ?
                """,
                (now, now, session_id),
            )
            conn.commit()

    await asyncio.to_thread(_touch)


async def get_snapshot(session_id: str) -> dict[str, Any] | None:
    await init_db()

    def _get() -> dict[str, Any] | None:
        with _connect() as conn:
            row = conn.execute(
                """
                SELECT session_id, text, done, error, created_at, last_poll, updated_at
                FROM stream_sessions
                WHERE session_id = ?
                """,
                (session_id,),
            ).fetchone()
            if row is None:
                return None
            return {
                "session_id": row["session_id"],
                "text": row["text"],
                "done": bool(row["done"]),
                "error": row["error"],
                "created_at": row["created_at"],
                "last_poll": row["last_poll"],
                "updated_at": row["updated_at"],
            }

    return await asyncio.to_thread(_get)


async def delete_older_than(age_seconds: int) -> int:
    await init_db()
    cutoff = time.time() - float(age_seconds)

    def _delete() -> int:
        with _connect() as conn:
            cur = conn.execute(
                """
                DELETE FROM stream_sessions
                WHERE updated_at < ?
                """,
                (cutoff,),
            )
            conn.commit()
            return int(cur.rowcount or 0)

    return await asyncio.to_thread(_delete)
