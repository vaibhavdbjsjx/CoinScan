"""
Request body size limits, enforced while the body is received.

Bodies are refused with 413 before multipart parsing or JSON decoding: a
declared Content-Length above the limit is rejected up front, and bodies sent
without one (chunked) are counted as they stream in. This bounds the memory
and temporary disk an upload can occupy before any endpoint code runs.
"""

from typing import Dict

from fastapi import HTTPException, status
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class BodyTooLarge(HTTPException):
    """Raised from the receive channel; FastAPI turns it into a 413 response."""

    def __init__(self, limit: int):
        super().__init__(
            status_code=413,
            detail=f"Request body exceeds the {limit // 1024} KB limit for this endpoint.",
        )


class RequestSizeLimitMiddleware:
    def __init__(self, app: ASGIApp, default_max_bytes: int, path_limits: Dict[str, int]):
        self.app = app
        self.default_max_bytes = default_max_bytes
        self.path_limits = path_limits

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        limit = self.path_limits.get(scope.get("path", ""), self.default_max_bytes)

        declared = None
        for name, value in scope.get("headers") or []:
            if name == b"content-length":
                try:
                    declared = int(value)
                except ValueError:
                    await self._respond(send, status.HTTP_400_BAD_REQUEST, "Invalid Content-Length header.")
                    return
                break
        if declared is not None and declared > limit:
            await self._respond(send, 413, BodyTooLarge(limit).detail)
            return

        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise BodyTooLarge(limit)
            return message

        await self.app(scope, limited_receive, send)

    @staticmethod
    async def _respond(send: Send, status_code: int, detail: str) -> None:
        import json

        body = json.dumps({"detail": detail}).encode("utf-8")
        await send({
            "type": "http.response.start",
            "status": status_code,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode("ascii")),
                (b"connection", b"close"),
            ],
        })
        await send({"type": "http.response.body", "body": body})
