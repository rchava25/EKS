import logging
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.routers import products

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Browse Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.monotonic()
    response = await call_next(request)
    logger.info(
        "method=%s path=%s status=%d duration_ms=%d",
        request.method, request.url.path, response.status_code,
        round((time.monotonic() - start) * 1000),
    )
    return response


app.include_router(products.router, prefix="/products", tags=["products"])


@app.get("/health")
def health():
    return {"status": "ok"}
