import asyncio
import time

from backend.settings import RATE_LIMIT_REQUESTS_PER_MINUTE


class SlidingWindowRateLimiter:
    def __init__(self, limit_per_minute: int | None = None) -> None:
        self._limit = int(limit_per_minute or RATE_LIMIT_REQUESTS_PER_MINUTE)
        self._lock = asyncio.Lock()
        self._hits: dict[str, list[float]] = {}

    async def allow(self, key: str) -> bool:
        if self._limit <= 0:
            return True

        now = time.monotonic()
        cutoff = now - 60.0

        async with self._lock:
            hits = self._hits.get(key)
            if hits is None:
                hits = []
                self._hits[key] = hits

            # drop old
            i = 0
            while i < len(hits) and hits[i] < cutoff:
                i += 1
            if i:
                del hits[:i]

            if len(hits) >= self._limit:
                return False

            hits.append(now)
            return True
