import logging
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.exceptions import AuthError, auth_error_handler, unhandled_error_handler
from app.routers import auth

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Login Service")

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
    duration_ms = round((time.monotonic() - start) * 1000)
    logger.info(
        "method=%s path=%s status_code=%d duration_ms=%d",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


app.add_exception_handler(AuthError, auth_error_handler)
app.add_exception_handler(Exception, unhandled_error_handler)

app.include_router(auth.router, prefix="/auth", tags=["auth"])


@app.get("/health")
def health():
    return {"status": "ok"}
