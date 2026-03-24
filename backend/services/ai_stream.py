import asyncio
import os
import time
import uuid
from collections.abc import Awaitable, Callable

from openai import APIError
from openai import AsyncOpenAI

from backend.services.generator import SYSTEM_PROMPT, _build_user_prompt
from backend.agents.planner import planner_agent
from backend.agents.builder import builder_agent_stream
from backend.agents.refiner import refiner_agent_stream
from backend.services import stream_sessions_store
from backend.settings import OPENAI_STREAM_TIMEOUT_SECONDS, SESSION_IDLE_TIMEOUT_SECONDS


_tasks_by_session_id: dict[str, asyncio.Task] = {}
_tasks_lock = asyncio.Lock()


async def _append_text(session_id: str, chunk: str) -> None:
    await stream_sessions_store.append_text(session_id=session_id, chunk=chunk)


async def _set_done(session_id: str, done: bool) -> None:
    await stream_sessions_store.set_done(session_id=session_id, done=done)


async def _touch_last_poll(session_id: str) -> None:
    await stream_sessions_store.touch_last_poll(session_id=session_id)


async def touch_session(session_id: str) -> None:
    await _touch_last_poll(session_id)


async def _set_error(session_id: str, error: str) -> None:
    await stream_sessions_store.set_error(session_id=session_id, error=error)


async def create_session(prompt: str) -> str:
    session_id = str(uuid.uuid4())
    await stream_sessions_store.create_session(session_id=session_id)
    return session_id


async def get_session_snapshot(session_id: str) -> dict[str, object] | None:
    snapshot = await stream_sessions_store.get_snapshot(session_id=session_id)
    if snapshot is None:
        return None
    return snapshot


async def cancel_session(session_id: str, reason: str = "") -> None:
    async with _tasks_lock:
        task = _tasks_by_session_id.get(session_id)

    if isinstance(task, asyncio.Task):
        task.cancel()
        await _set_error(session_id, reason or "Cancelled")


async def stream_to_session(session_id: str, prompt: str) -> None:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        await _set_error(session_id, "OPENAI_API_KEY is not set")
        return

    try:
        client = AsyncOpenAI(api_key=api_key)

        async with asyncio.timeout(OPENAI_STREAM_TIMEOUT_SECONDS):
            stream = await client.chat.completions.create(
                model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": _build_user_prompt(prompt=prompt, previous_code=None)},
                ],
                stream=True,
                temperature=0.2,
            )

            token_count = 0

            async for event in stream:
                delta = event.choices[0].delta
                content = getattr(delta, "content", None)
                if content:
                    await _append_text(session_id, content)
                    token_count += 1

                if token_count % 25 == 0:
                    snapshot = await get_session_snapshot(session_id)
                    if snapshot and not bool(snapshot.get("done", False)):
                        last_poll = float(snapshot.get("last_poll", time.time()))
                        if (time.time() - last_poll) > SESSION_IDLE_TIMEOUT_SECONDS:
                            await _set_error(session_id, "Client disconnected (idle)")
                            return

        await _set_done(session_id, True)

    except TimeoutError:
        await _set_error(session_id, "Stream timed out")
    except asyncio.CancelledError:
        await _set_error(session_id, "Stream cancelled")
        raise

    except APIError as e:
        await _set_error(session_id, f"OpenAI API error: {e}")
    except Exception as e:
        await _set_error(session_id, f"Unexpected error: {e}")


async def stream_to_session_refine(session_id: str, prompt: str, previous_code: str) -> None:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        await _set_error(session_id, "OPENAI_API_KEY is not set")
        return

    try:
        async with asyncio.timeout(OPENAI_STREAM_TIMEOUT_SECONDS):
            token_count = 0
            async for token in refiner_agent_stream(prompt=prompt, previous_code=previous_code):
                await _append_text(session_id, token)
                token_count += 1

                if token_count % 25 == 0:
                    snapshot = await get_session_snapshot(session_id)
                    if snapshot and not bool(snapshot.get("done", False)):
                        last_poll = float(snapshot.get("last_poll", time.time()))
                        if (time.time() - last_poll) > SESSION_IDLE_TIMEOUT_SECONDS:
                            await _set_error(session_id, "Client disconnected (idle)")
                            return

        await _set_done(session_id, True)

    except TimeoutError:
        await _set_error(session_id, "Stream timed out")
    except asyncio.CancelledError:
        await _set_error(session_id, "Stream cancelled")
        raise
    except Exception as e:
        await _set_error(session_id, f"Unexpected error: {e}")


async def stream_to_session_live(session_id: str, prompt: str) -> None:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        await _set_error(session_id, "OPENAI_API_KEY is not set")
        return

    try:
        async with asyncio.timeout(OPENAI_STREAM_TIMEOUT_SECONDS):
            plan = await planner_agent(prompt)
            steps = list(plan.get("steps", [])) if isinstance(plan, dict) else []

            if not steps:
                await _append_text(session_id, "[Step 1] Planning...\n")
                await _append_text(session_id, "-- Planner returned no steps, using fallback step.\n")
                steps = [{
                    "title": "ServerScriptService/AI/MainGame",
                    "description": prompt,
                }]

            token_count = 0
            for idx, step in enumerate(steps, start=1):
                title = str(step.get("title", f"Step {idx}")) if isinstance(step, dict) else f"Step {idx}"
                description = str(step.get("description", "")) if isinstance(step, dict) else ""

                await _append_text(session_id, f"[Step {idx}] {title}...\n")

                async for token in builder_agent_stream(
                    step_title=title,
                    step_request=(description or prompt),
                    previous_code=None,
                ):
                    await _append_text(session_id, token)
                    token_count += 1

                    if token_count % 25 == 0:
                        snapshot = await get_session_snapshot(session_id)
                        if snapshot and not bool(snapshot.get("done", False)):
                            last_poll = float(snapshot.get("last_poll", time.time()))
                            if (time.time() - last_poll) > SESSION_IDLE_TIMEOUT_SECONDS:
                                await _set_error(session_id, "Client disconnected (idle)")
                                return

                await _append_text(session_id, "\n\n")

        await _set_done(session_id, True)

    except TimeoutError:
        await _set_error(session_id, "Stream timed out")
    except asyncio.CancelledError:
        await _set_error(session_id, "Stream cancelled")
        raise

    except APIError as e:
        await _set_error(session_id, f"OpenAI API error: {e}")
    except Exception as e:
        await _set_error(session_id, f"Unexpected error: {e}")


async def start_background_stream(session_id: str, prompt: str) -> None:
    loop = asyncio.get_running_loop()

    def _schedule(coro_factory: Callable[[], Awaitable[None]]) -> None:
        task = loop.create_task(coro_factory())

        async def _store_task() -> None:
            async with _tasks_lock:
                _tasks_by_session_id[session_id] = task

        loop.create_task(_store_task())

    _schedule(lambda: stream_to_session(session_id=session_id, prompt=prompt))


async def start_background_stream_live(session_id: str, prompt: str) -> None:
    loop = asyncio.get_running_loop()

    def _schedule(coro_factory: Callable[[], Awaitable[None]]) -> None:
        task = loop.create_task(coro_factory())

        async def _store_task() -> None:
            async with _tasks_lock:
                _tasks_by_session_id[session_id] = task

        loop.create_task(_store_task())

    _schedule(lambda: stream_to_session_live(session_id=session_id, prompt=prompt))


async def start_background_stream_refine(session_id: str, prompt: str, previous_code: str) -> None:
    loop = asyncio.get_running_loop()

    def _schedule(coro_factory: Callable[[], Awaitable[None]]) -> None:
        task = loop.create_task(coro_factory())

        async def _store_task() -> None:
            async with _tasks_lock:
                _tasks_by_session_id[session_id] = task

        loop.create_task(_store_task())

    _schedule(
        lambda: stream_to_session_refine(
            session_id=session_id,
            prompt=prompt,
            previous_code=previous_code,
        )
    )
