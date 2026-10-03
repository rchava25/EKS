import logging

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class NotFoundError(Exception):
    def __init__(self, message: str = "Not found"):
        self.message = message


class ConflictError(Exception):
    def __init__(self, message: str = "Conflict"):
        self.message = message


class BadRequestError(Exception):
    def __init__(self, message: str = "Bad request"):
        self.message = message


async def not_found_handler(request: Request, exc: NotFoundError) -> JSONResponse:
    return JSONResponse(
        status_code=404,
        content={"error": exc.message, "status_code": 404},
    )


async def conflict_handler(request: Request, exc: ConflictError) -> JSONResponse:
    return JSONResponse(
        status_code=409,
        content={"error": exc.message, "status_code": 409},
    )


async def bad_request_handler(request: Request, exc: BadRequestError) -> JSONResponse:
    return JSONResponse(
        status_code=400,
        content={"error": exc.message, "status_code": 400},
    )


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={"error": "Validation error", "status_code": 422},
    )


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s %s: %s", request.method, request.url.path, exc)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error", "status_code": 500},
    )
