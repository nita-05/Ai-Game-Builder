import asyncio
import json
import os
import sqlite3
import time
import uuid


DB_PATH = os.getenv(
    "MEMORY_DB_PATH",
    os.path.join(os.path.dirname(os.path.dirname(__file__)), "memory.db"),
)


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def _init_db_sync() -> None:
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS builds (
                id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                prompt TEXT NOT NULL,
                steps_json TEXT,
                scripts_json TEXT,
                status TEXT,
                metadata_json TEXT
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS user_prefs (
                user_id TEXT PRIMARY KEY,
                updated_at REAL NOT NULL,
                prefs_json TEXT NOT NULL
            )
            """
        )
        conn.commit()
    finally:
        conn.close()


async def init_db() -> None:
    await asyncio.to_thread(_init_db_sync)


def _row_to_dict(row: sqlite3.Row) -> dict:
    return {k: row[k] for k in row.keys()}


def _save_build_sync(
    prompt: str,
    steps: object | None,
    scripts: object | None,
    status: str | None,
    metadata: object | None,
) -> str:
    build_id = str(uuid.uuid4())
    created_at = time.time()

    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO builds (id, created_at, prompt, steps_json, scripts_json, status, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                build_id,
                created_at,
                prompt,
                json.dumps(steps) if steps is not None else None,
                json.dumps(scripts) if scripts is not None else None,
                status,
                json.dumps(metadata) if metadata is not None else None,
            ),
        )
        conn.commit()
        return build_id
    finally:
        conn.close()


async def save_build(
    prompt: str,
    steps: object | None = None,
    scripts: object | None = None,
    status: str | None = None,
    metadata: object | None = None,
) -> str:
    await init_db()
    return await asyncio.to_thread(_save_build_sync, prompt, steps, scripts, status, metadata)


def _list_builds_sync(limit: int, offset: int) -> list[dict]:
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, created_at, prompt, status
            FROM builds
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
            """,
            (limit, offset),
        )
        return [_row_to_dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


async def list_builds(limit: int = 20, offset: int = 0) -> list[dict]:
    await init_db()
    return await asyncio.to_thread(_list_builds_sync, limit, offset)


def _get_build_sync(build_id: str) -> dict | None:
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM builds WHERE id = ?", (build_id,))
        row = cur.fetchone()
        if not row:
            return None
        data = _row_to_dict(row)
        for key in ("steps_json", "scripts_json", "metadata_json"):
            if data.get(key):
                try:
                    data[key] = json.loads(data[key])
                except Exception:
                    pass
        return data
    finally:
        conn.close()


async def get_build(build_id: str) -> dict | None:
    await init_db()
    return await asyncio.to_thread(_get_build_sync, build_id)


def _set_style_sync(user_id: str, prefs: object) -> None:
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO user_prefs (user_id, updated_at, prefs_json)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET updated_at=excluded.updated_at, prefs_json=excluded.prefs_json
            """,
            (user_id, time.time(), json.dumps(prefs)),
        )
        conn.commit()
    finally:
        conn.close()


async def set_style(user_id: str, prefs: object) -> None:
    await init_db()
    await asyncio.to_thread(_set_style_sync, user_id, prefs)


def _get_style_sync(user_id: str) -> dict | None:
    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT user_id, updated_at, prefs_json FROM user_prefs WHERE user_id = ?", (user_id,))
        row = cur.fetchone()
        if not row:
            return None
        data = _row_to_dict(row)
        try:
            data["prefs_json"] = json.loads(data["prefs_json"]) if data.get("prefs_json") else {}
        except Exception:
            pass
        return data
    finally:
        conn.close()


async def get_style(user_id: str) -> dict | None:
    await init_db()
    return await asyncio.to_thread(_get_style_sync, user_id)
