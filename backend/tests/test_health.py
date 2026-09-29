import pytest
from fastapi.testclient import TestClient
from backend.app.main import app

client = TestClient(app)


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["service"] == "coinscan-backend"
    assert "version" in data
    assert "providers" in data
    assert "timestamp" in data


def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert "docs" in data


def test_cors_headers_wildcard_security():
    """Verify that wildcard CORS does not allow credentials, adhering to Fetch spec."""
    response = client.options(
        "/health",
        headers={
            "Origin": "https://example.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "*"
    # Under wildcard origin, allow-credentials must not be 'true'
    assert response.headers.get("access-control-allow-credentials") != "true"

