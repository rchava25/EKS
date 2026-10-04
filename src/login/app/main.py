import logging
import os
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from app.exceptions import AuthError, auth_error_handler, unhandled_error_handler
from app.routers import auth

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── OpenTelemetry tracing ─────────────────────────────────────────────────────
# Sends traces to the ADOT sidecar collector (localhost:4317).
# The collector forwards to AWS X-Ray. Set OTEL_SDK_DISABLED=true to opt out.

_resource = Resource.create({
    "service.name": "login-service",
    "deployment.environment": os.getenv("ENV", "dev"),
})
_provider = TracerProvider(resource=_resource)
_otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=_otlp_endpoint)))
trace.set_tracer_provider(_provider)

BotocoreInstrumentor().instrument()

app = FastAPI(title="Login Service")

FastAPIInstrumentor.instrument_app(app, tracer_provider=_provider)

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
