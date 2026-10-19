import os
from fastapi import FastAPI, Header, HTTPException

app = FastAPI(title="Azure APIM Demo API", version="1.0.0")


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok", "service": "python-api"}


@app.get("/api/v1/hello", tags=["demo"])
def hello(
    x_gateway_key: str | None = Header(default=None, alias="X-Gateway-Key"),
    x_user_id: str | None = Header(default=None, alias="X-Authenticated-User"),
    x_user_name: str | None = Header(default=None, alias="X-Authenticated-Name"),
):
    expected = os.environ.get("BACKEND_SHARED_KEY", "")
    if not expected or x_gateway_key != expected:
        raise HTTPException(status_code=403, detail="Request must come through the configured API gateway")
    return {
        "message": "Hello from the Python backend.",
        "service": "python-api",
        "authenticatedUser": {"id": x_user_id, "name": x_user_name},
        "requestPath": "/api/v1/hello",
    }
