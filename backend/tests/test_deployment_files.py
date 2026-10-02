"""
Static checks for the deployment files: the container honours $PORT, starts one
worker by default, keeps the FastAPI entry point, ships no test tools, and the
build context and env templates never carry secrets.
"""

import re
from pathlib import Path

from backend.app.main import app

ROOT = Path(__file__).resolve().parents[2]
DOCKERFILE = (ROOT / "backend" / "Dockerfile").read_text()
RAILWAY = (ROOT / "railway.toml").read_text()


def _cmd_line() -> str:
    return next(line for line in DOCKERFILE.splitlines() if line.startswith("CMD "))


def test_container_binds_the_platform_port_with_one_worker_by_default():
    cmd = _cmd_line()
    assert "exec uvicorn backend.app.main:app" in cmd
    assert "--host 0.0.0.0" in cmd
    assert '--port \\"${PORT:-8080}\\"' in cmd
    assert '--workers \\"${WEB_CONCURRENCY:-1}\\"' in cmd
    assert "--timeout-graceful-shutdown" in cmd
    assert "--no-proxy-headers" in cmd
    assert '"--port", "8080"' not in DOCKERFILE


def test_dependencies_are_installed_where_the_runtime_user_finds_them():
    """`pip install --user` as root lands in /root/.local, which the non-root
    runtime user (home /app) never searches: the server would not start."""
    instructions = "\n".join(line for line in DOCKERFILE.splitlines() if not line.lstrip().startswith("#"))
    assert "--user" not in instructions
    assert "python -m venv /opt/venv" in DOCKERFILE
    assert "/opt/venv/bin/pip install --no-cache-dir -r requirements.txt" in DOCKERFILE
    assert "COPY --from=builder /opt/venv /opt/venv" in DOCKERFILE
    assert re.search(r"^ENV PATH=/opt/venv/bin:\$PATH$", DOCKERFILE, re.MULTILINE)
    # Both stages use the same base image, so the copied virtualenv's interpreter exists.
    bases = re.findall(r"^FROM (\S+)", DOCKERFILE, re.MULTILINE)
    assert len(bases) == 2 and bases[0] == bases[1]
    # The server runs as the unprivileged user.
    assert "USER coinscan" in DOCKERFILE
    assert DOCKERFILE.index("USER coinscan") < DOCKERFILE.index("CMD ")


def test_runtime_dependencies_are_pinned_to_tested_versions():
    lines = [line.split("#", 1)[0].strip()
             for line in (ROOT / "backend" / "requirements.txt").read_text().splitlines()]
    requirements = [line for line in lines if line]
    assert requirements
    for requirement in requirements:
        assert re.fullmatch(r"[A-Za-z0-9_.\-]+(\[[a-z,]+\])?==[0-9][0-9A-Za-z.]*", requirement), requirement


def test_container_healthcheck_follows_the_port():
    assert "${PORT:-8080}/health/live" in DOCKERFILE


def test_production_image_ships_no_test_tools():
    runtime = (ROOT / "backend" / "requirements.txt").read_text().lower()
    assert "pytest" not in runtime and "aiosqlite" not in runtime
    dev = (ROOT / "backend" / "requirements-dev.txt").read_text()
    assert "-r requirements.txt" in dev and "pytest" in dev and "aiosqlite" in dev


def test_railway_config_points_at_real_files_and_routes():
    assert 'builder = "DOCKERFILE"' in RAILWAY
    dockerfile = re.search(r'dockerfilePath = "([^"]+)"', RAILWAY).group(1)
    assert (ROOT / dockerfile).is_file()
    health = re.search(r'healthcheckPath = "([^"]+)"', RAILWAY).group(1)
    assert health in {route.path for route in app.routes}
    draining = int(re.search(r'drainingSeconds = "(\d+)"', RAILWAY).group(1))
    graceful = int(re.search(r"GRACEFUL_SHUTDOWN_SECONDS:-(\d+)", _cmd_line()).group(1))
    assert draining > graceful


def test_docker_build_context_excludes_everything_but_the_api():
    rules = [line.strip() for line in (ROOT / ".dockerignore").read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    assert rules[0] == "*"
    assert set(r for r in rules if r.startswith("!")) == {"!backend/requirements.txt", "!backend/app/"}
    assert "**/.env" in rules and "**/.env.*" in rules


def test_env_templates_hold_no_values_and_keep_secrets_server_side():
    secret_names = ("DATABASE_URL", "SUPABASE_JWT_SECRET", "SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY",
                    "OPENAI_API_KEY",
                    "NUMISTA_API_KEY", "METALS_API_KEY", "EXCHANGERATE_API_KEY", "GUEST_QUOTA_HMAC_SECRET",
                    "REVENUECAT_WEBHOOK_SECRET", "GEMINI_API_KEY", "API_SECRET", "API_KEYS_JSON")
    server = (ROOT / "backend" / ".env.example").read_text()
    for name in secret_names:
        match = re.search(rf"^{name}=(.*)$", server, re.MULTILINE)
        assert match is not None, f"{name} missing from backend/.env.example"
        assert match.group(1).strip() == "", f"{name} must be an empty placeholder"

    client = (ROOT / ".env.example").read_text()
    for name in secret_names:
        assert not re.search(rf"^\s*{name}\s*=", client, re.MULTILINE), f"{name} must never be a client variable"
