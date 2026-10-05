import logging
import threading
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.routers import shipping
from app import consumer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Shipping Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "PATCH", "OPTIONS"],
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


@app.on_event("startup")
def start_consumer():
    t = threading.Thread(target=consumer.run, daemon=True)
    t.start()
    logger.info("SQS consumer thread started")


app.include_router(shipping.router, prefix="/shipping", tags=["shipping"])


@app.get("/health")
def health():
    return {"status": "ok"}
