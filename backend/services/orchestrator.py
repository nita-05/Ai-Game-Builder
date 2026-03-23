from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from collections.abc import AsyncIterator

from backend.agents.builder import builder_agent, builder_agent_stream
from backend.agents.debugger import debugger_agent, debugger_agent_code
from backend.agents.planner import planner_agent
from backend.agents.refiner import refiner_agent, refiner_agent_code
from backend.agents.validator import validator_agent


@dataclass
class OrchestratorState:
    prompt: str
    steps: list[dict] = field(default_factory=list)
    current_step: int | None = None
    code: str = ""
    code_steps: list[dict] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    previous_code: str | None = None


async def run_orchestrator(prompt: str, previous_code: str | None = None) -> OrchestratorState:
    state = OrchestratorState(prompt=prompt, previous_code=previous_code)

    if previous_code:
        refined = await refiner_agent(prompt=prompt, previous_code=previous_code)
        state.code_steps = list(refined.get("steps", [])) if isinstance(refined, dict) else []
        state.current_step = None
        state.code = "\n\n".join(
            [str(s.get("code", "")) for s in state.code_steps if isinstance(s, dict)]
        )
        return state

    plan = await planner_agent(prompt)
    state.steps = list(plan.get("steps", [])) if isinstance(plan, dict) else []

    built = await builder_agent(prompt=prompt, plan=plan)
    state.code_steps = list(built.get("steps", [])) if isinstance(built, dict) else []
    state.current_step = None
    state.code = "\n\n".join([str(s.get("code", "")) for s in state.code_steps if isinstance(s, dict)])
    return state


async def run_debugger(error_message: str, code: str) -> str:
    result = await debugger_agent(error_message=error_message, code=code)
    fixed = result.get("fixed_code") if isinstance(result, dict) else None
    return fixed or ""


async def run_refiner(prompt: str, existing_code: str) -> str:
    return await refiner_agent_code(prompt=prompt, existing_code=existing_code)


async def orchestrate_stream(prompt: str) -> AsyncIterator[dict]:
    state = OrchestratorState(prompt=prompt)

    plan = await planner_agent(prompt)
    state.steps = list(plan.get("steps", [])) if isinstance(plan, dict) else []
    yield {"type": "plan", "state": _state_snapshot(state)}

    full_code_parts: list[str] = []

    for idx, step in enumerate(state.steps):
        state.current_step = idx
        title = str(step.get("title", f"Step {idx + 1}")) if isinstance(step, dict) else f"Step {idx + 1}"
        description = (
            str(step.get("description", "")) if isinstance(step, dict) else ""
        )

        yield {
            "type": "step_start",
            "step_index": idx,
            "title": title,
            "state": _state_snapshot(state),
        }

        step_code = ""
        validator_task = None
        try:
            async for token in builder_agent_stream(
                step_title=title,
                step_request=(description or prompt),
                previous_code=None,
            ):
                step_code += token
                yield {
                    "type": "token",
                    "step_index": idx,
                    "title": title,
                    "token": token,
                    "state": _state_snapshot(state),
                }
        except Exception as e:
            err = f"Builder error on step '{title}': {e}"
            state.errors.append(err)
            yield {"type": "error", "error": err, "state": _state_snapshot(state)}

        if validator_task is None:
            validator_task = asyncio.create_task(validator_agent(title=title, code=step_code))

        step_entry = {"title": title, "code": step_code}
        state.code_steps.append(step_entry)

        full_code_parts.append(step_code)
        state.code = "\n\n".join(full_code_parts)

        yield {
            "type": "step_end",
            "step_index": idx,
            "title": title,
            "state": _state_snapshot(state),
        }

        if validator_task is not None:
            try:
                result = await validator_task
                warnings = result.get("warnings", []) if isinstance(result, dict) else []
                errors = result.get("errors", []) if isinstance(result, dict) else []
                if warnings:
                    yield {
                        "type": "validation_warnings",
                        "step_index": idx,
                        "title": title,
                        "warnings": warnings,
                        "state": _state_snapshot(state),
                    }
                if errors:
                    yield {
                        "type": "validation_errors",
                        "step_index": idx,
                        "title": title,
                        "errors": errors,
                        "state": _state_snapshot(state),
                    }
            except Exception as e:
                yield {
                    "type": "validation_error",
                    "step_index": idx,
                    "title": title,
                    "error": str(e),
                    "state": _state_snapshot(state),
                }

    state.current_step = None
    yield {"type": "done", "state": _state_snapshot(state)}


async def orchestrate_refine_stream(prompt: str, existing_code: str) -> AsyncIterator[dict]:
    state = OrchestratorState(prompt=prompt, previous_code=existing_code)
    yield {"type": "refine_start", "state": _state_snapshot(state)}

    try:
        updated = await refiner_agent_code(prompt=prompt, existing_code=existing_code)
        state.code = updated
        yield {"type": "refine_done", "state": _state_snapshot(state)}
    except Exception as e:
        err = f"Refiner error: {e}"
        state.errors.append(err)
        yield {"type": "error", "error": err, "state": _state_snapshot(state)}


async def orchestrate_debug_stream(error_message: str, code: str) -> AsyncIterator[dict]:
    state = OrchestratorState(prompt="", previous_code=code)
    yield {"type": "debug_start", "state": _state_snapshot(state)}

    try:
        fixed = await debugger_agent_code(error_message=error_message, code=code)
        state.code = fixed
        yield {"type": "debug_done", "state": _state_snapshot(state)}
    except Exception as e:
        err = f"Debugger error: {e}"
        state.errors.append(err)
        yield {"type": "error", "error": err, "state": _state_snapshot(state)}


def _state_snapshot(state: OrchestratorState) -> dict:
    return {
        "steps": state.steps,
        "current_step": state.current_step,
        "code": state.code,
        "errors": state.errors,
    }
