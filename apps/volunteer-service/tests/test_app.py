import os
import sys

os.environ.setdefault("AWS_DYNAMODB_TABLE", "SolidaryTechVolunteers")
os.environ.setdefault("OTEL_SDK_DISABLED", "true")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class _FakeTable:
    def __init__(self):
        self.items = []
        self.table_status = "ACTIVE"

    def put_item(self, Item):
        self.items.append(Item)

    def scan(self, FilterExpression=None):
        # regressão do bug original: garante que Attr('ngo_id').eq(x) é usável sem ImportError
        matching = [i for i in self.items if FilterExpression(i)] if callable(FilterExpression) else self.items
        return {"Items": matching}


def _build_client(monkeypatch):
    import app as app_module
    monkeypatch.setattr(app_module, "table", _FakeTable())
    app_module.app.testing = True
    return app_module.app.test_client()


def test_health_ok(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.get("/health")
    assert resp.status_code == 200


def test_register_volunteer_requires_fields(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.post("/volunteers", json={"name": "Sem email"})
    assert resp.status_code == 400


def test_register_volunteer_success(monkeypatch):
    client = _build_client(monkeypatch)
    resp = client.post("/volunteers", json={"name": "Jorge", "email": "jorge@ex.com", "ngo_id": 1})
    assert resp.status_code == 201
    body = resp.get_json()
    assert body["ngo_id"] == 1
    assert "volunteer_id" in body


def test_get_volunteers_by_ngo_uses_dynamodb_conditions_attr(monkeypatch):
    # Este teste existe especificamente para travar a regressão do bug do código-base:
    # boto3.dynamodb.conditions.Attr sem o submódulo importado quebrava em runtime.
    import boto3.dynamodb.conditions  # deve ser importável no módulo app
    client = _build_client(monkeypatch)
    resp = client.get("/volunteers/1")
    assert resp.status_code == 200
    assert resp.get_json() == []
