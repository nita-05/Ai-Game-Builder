from fastapi import FastAPI

from routes.generate import router as generate_router

app = FastAPI(title="Streaming Generator API")

app.include_router(generate_router)
