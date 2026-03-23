from dotenv import load_dotenv
from fastapi import FastAPI
import asyncio
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

load_dotenv()
load_dotenv("backend/.env")

from backend.routes.debug import router as debug_router
from backend.routes.generate import router as generate_router
from backend.routes.fix import router as fix_router
from backend.routes.memory import router as memory_router
from backend.routes.orchestrate import router as orchestrate_router
from backend.routes.stream import router as stream_router
from backend.routes.tools import router as tools_router
from backend.settings import APP_API_KEY
from backend.services.rate_limiter import SlidingWindowRateLimiter
from backend.services import stream_sessions_store
from backend.settings import STREAM_SESSION_RETENTION_SECONDS

app = FastAPI(title="Streaming Generator API")


_rate_limiter = SlidingWindowRateLimiter()


class RateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if path in {
            "/start",
            "/start_live",
            "/refine_start",
            "/generate",
            "/fix",
            "/debug",
            "/tools/plan",
            "/orchestrate/stream",
        }:
            ip = request.client.host if request.client else "unknown"
            key = f"{ip}:{path}"
            allowed = await _rate_limiter.allow(key)
            if not allowed:
                return JSONResponse({"detail": "Rate limit exceeded"}, status_code=429)

        return await call_next(request)


class ApiKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if not APP_API_KEY:
            return await call_next(request)

        path = request.url.path
        if path in {"/", "/health", "/docs", "/redoc", "/openapi.json"}:
            return await call_next(request)

        api_key = request.headers.get("x-api-key")
        if api_key != APP_API_KEY:
            return JSONResponse({"detail": "Unauthorized"}, status_code=401)

        return await call_next(request)


app.add_middleware(ApiKeyMiddleware)
app.add_middleware(RateLimitMiddleware)


@app.on_event("startup")
async def _startup_cleanup_task() -> None:
    async def _loop() -> None:
        while True:
            try:
                await stream_sessions_store.delete_older_than(STREAM_SESSION_RETENTION_SECONDS)
            except Exception:
                pass
            await asyncio.sleep(60)

    asyncio.create_task(_loop())


@app.get("/")
async def root() -> dict:
    return {"status": "ok"}


@app.get("/health")
async def health() -> dict:
    return {"status": "healthy"}

app.include_router(generate_router)
app.include_router(fix_router)
app.include_router(debug_router)
app.include_router(memory_router)
app.include_router(orchestrate_router)
app.include_router(stream_router)
app.include_router(tools_router)
