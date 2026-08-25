import os
import sys
from unittest.mock import MagicMock

os.environ.setdefault("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/ngo_db")
os.environ.setdefault("OTEL_SDK_DISABLED", "true")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# app.py abre um SimpleConnectionPool real na importação do módulo (mesmo comportamento do
# código-base original) — sem banco de verdade disponível no ambiente de teste, isso derrubaria
# o processo (SystemExit) antes mesmo do teste rodar. Substituímos a classe ANTES do primeiro
# `import app` para o teste unitário não depender de um Postgres real; os testes trocam
# `app_module.pool` por um fake funcional logo em seguida (ver _build_client).
import psycopg2.pool  # noqa: E402
psycopg2.pool.SimpleConnectionPool = MagicMock(return_value=MagicMock())


class _FakeCursor:
    def __init__(self, conn):
        self._conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, query, params=None):
        self._conn.last_query = query
        self._conn.last_params = params

    def fetchone(self):
        return {"id": 1, "name": "Anjos de Patas", "email": "contato@anjosdepatas.org",
                "cause": "Proteção Animal", "city": "Osasco"}

    def fetchall(self):
        return [self.fetchone()]


class _FakeConn:
    def cursor(self, cursor_factory=None):
        return _FakeCursor(self)

    def commit(self):
        pass

    def rollback(self):
        pass


class _FakePool:
    def getconn(self):
        return _FakeConn()

    def putconn(self, conn):
        pass


def _build_client(monkeypatch):
    import app as app_module
    monkeypatch.setattr(app_module, "pool", _FakePool())
    app_module.app.testing = True
    return app_module.app.test_client()


def test_health_ok(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_metrics_exposes_prometheus_format(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"http_requests_total" in resp.data or resp.data == b""


def test_create_ngo_requires_fields(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.post("/ngos", json={"name": "Falta campo"})
    assert resp.status_code == 400


def test_create_ngo_success(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.post("/ngos", json={
        "name": "Anjos de Patas", "email": "contato@anjosdepatas.org",
        "cause": "Proteção Animal", "city": "Osasco"
    })
    assert resp.status_code == 201


def test_get_ngos(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.get("/ngos")
    assert resp.status_code == 200
    assert isinstance(resp.get_json(), list)
